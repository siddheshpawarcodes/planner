import 'package:flutter_test/flutter_test.dart';
import 'package:planner_app/domain/category.dart';
import 'package:planner_app/domain/intents.dart';
import 'package:planner_app/domain/routine.dart';
import 'package:planner_app/domain/scheduler.dart';
import 'package:planner_app/domain/task.dart';
import 'package:planner_app/domain/time.dart';

import 'fixtures.dart';

VoiceResolution say(String s, List<Task> tasks, {int? today, num now = 1180}) {
  final d = today ?? tue;
  return resolveIntent(parseUtterance(s, today: d),
      tasks: tasks, routine: routine, today: d, now: now, newId: idGen());
}

List<Task> wedPlan() => [
      ...inbox(),
      Task.make('t1', 'Study polity', Category.study, wed, 1200, 120, source: Source.voice),
      Task.make('t2', 'Exercise', Category.body, wed, 1335, 45, source: Source.voice),
      Task.make('t3', 'Learn Flutter', Category.build, wed, 1380, 60, source: Source.voice),
    ];

void main() {
  group('normalize', () {
    test('number words and durations', () {
      expect(normalizeUtterance('study polity for two hours'), 'study polity for 2 hours');
      expect(normalizeUtterance('forty five minutes'), '45 minutes');
      expect(normalizeUtterance('forty-five minutes'), '45 minutes');
      expect(normalizeUtterance('an hour and a half'), '90 minutes');
      expect(normalizeUtterance('half an hour'), '30 minutes');
      expect(normalizeUtterance('two and a half hours'), '2.5 hours');
      expect(normalizeUtterance('for an hour'), 'for 1 hour');
    });
  });

  group('the nine demo lines', () {
    test('three-task request → tomorrow evening in the order spoken', () {
      final i = parseUtterance(demoUtterances[0], today: tue);
      expect(i.kind, IntentKind.add);
      expect([for (final t in i.tasks) (t.title, t.duration)],
          [('Study polity', 120), ('Exercise', 45), ('Learn Flutter', 60)]);
      expect(i.keywords, containsAll(['tomorrow', 'study', 'polity', '2', 'hours', 'exercise', '45', 'flutter']));
      final r = say(demoUtterances[0], inbox());
      expect(r.label, 'TOMORROW EVENING');
      expect([for (final x in r.rows) '${x.title} ${x.detail}'],
          ['Study polity 2h, 20:00', 'Exercise 45m, 22:15', 'Learn Flutter 1h, 23:00']);
      expect(r.doneLabel, 'SCHEDULED FOR TOMORROW');
      expect(r.wait, VoiceWait.none);
      expect(r.core, Category.study);
      final e = r.effect as PlaceEffect;
      expect(e.day, wed);
      expect(e.ids.length, 3);
    });

    test('Add gym tomorrow for one hour', () {
      final r = say(demoUtterances[1], inbox());
      expect(r.rows.single.title, 'Gym');
      expect(r.rows.single.detail, '1h, 20:00');
      expect(r.label, 'TOMORROW EVENING');
    });

    test('Add gym tomorrow when tomorrow is full finds the next free hour', () {
      final r = say(demoUtterances[1], [
        Task.make('x', 'Deep work', Category.build, wed, 1200, 210),
      ]);
      expect(r.label, 'NEXT FREE TIME');
      expect(r.rows.single.detail, '1h, Thu 1, 20:00');
      expect(r.summary, 'Tomorrow evening is full, so Planner found the next free hour.');
    });

    test('Move gym to Saturday finds the next gym or exercise task', () {
      final r = say(demoUtterances[2], wedPlan());
      expect(r.label, 'MOVE');
      expect(r.rows.single.title, 'Exercise');
      expect(r.rows.single.detail, 'Wed 30 22:15 → Sat 09:00');
      expect(r.doneLabel, 'MOVED TO SATURDAY');
      final e = r.effect as MoveEffect;
      expect((e.toDay, e.slot.start), (sat, 540));
    });

    test('Mark gym complete only looks at today', () {
      expect(say(demoUtterances[3], wedPlan()).label, 'NOT FOUND');
      expect(say(demoUtterances[3], wedPlan()).summary,
          "There's no gym task on your plan today. Try “Add gym tomorrow for one hour.”");
      final r = say(demoUtterances[3], wedPlan(), today: wed, now: 1300);
      expect(r.label, 'COMPLETE');
      expect((r.effect as CompleteEffect).taskId, 't2');
    });

    test('Delete my gym task always confirms', () {
      final r = say(demoUtterances[4], wedPlan());
      expect(r.label, 'DELETE THIS TASK?');
      expect(r.wait, VoiceWait.confirm);
      expect((r.yes, r.no), ('Delete Exercise', 'Keep it'));
    });

    test('What do I have tomorrow?', () {
      final r = say(demoUtterances[5], wedPlan());
      expect(r.label, 'TOMORROW, WEDNESDAY');
      expect(r.rows.length, 3);
      expect(r.summary, '3h 45m planned, 2h 55m realistic.');
      expect((r.yes, r.no), ('Open tomorrow', 'Done'));
      final empty = say(demoUtterances[5], inbox());
      expect(empty.rows.single.title, 'Office');
      expect(empty.summary, 'Nothing planned yet. 3h 10m of realistic time is open.');
    });

    test('Plan my evening places inbox tasks tonight until capacity runs out', () {
      final r = say(demoUtterances[6], inbox());
      expect(r.label, 'TONIGHT');
      expect([for (final x in r.rows) x.detail], ['45m, 20:00', '30m, 20:45', '20m, 21:15']);
      expect(r.doneLabel, 'PLANNED FOR TONIGHT');
      final none = say(demoUtterances[6], const []);
      expect(none.summary, 'Nothing is waiting to be scheduled.');
    });

    test('Reschedule unfinished tasks', () {
      final r = say(demoUtterances[7], wedPlan(), today: wed, now: 1385);
      expect(r.label, 'RESCHEDULE');
      expect(r.rows.length, 2, reason: 'Flutter runs to 00:00, so only two are past');
      expect(say(demoUtterances[7], inbox()).label, 'ALL CLEAR');
    });

    test('Add a recurring gym session every Monday', () {
      final i = parseUtterance(demoUtterances[8], today: tue);
      expect(i.kind, IntentKind.recur);
      expect(i.rule, const DayRule.on(0));
      expect(i.tasks.single.title, 'Gym');
      final r = say(demoUtterances[8], inbox());
      expect(r.label, 'EVERY MONDAY');
      expect(r.rows.single.detail, '1h, 20:00 → 21:00');
      expect(r.summary, 'Starts Monday 5 October. It repeats until you stop it.');
      expect(r.doneLabel, 'REPEATS EVERY MONDAY');
      final e = r.effect as SeriesEffect;
      expect(e.series.from, mon + 7);
      expect(e.occurrences.first.day, mon + 7);
    });
  });

  group('beyond the demo lines', () {
    test('times, days and preferences', () {
      final i = parseUtterance('Call mum on Friday at 7pm for half an hour', today: tue);
      expect(i.tasks.single.title, 'Call mum');
      expect(i.tasks.single.duration, 30);
      expect(i.tasks.single.day, fri);
      expect(i.tasks.single.at, 1140);
      expect(guessCat('Call mum'), Category.people);
      final j = parseUtterance('Read tonight', today: tue);
      expect(j.tasks.single.title, 'Read');
      expect(j.day, tue);
      expect(parseUtterance('Move the report to tomorrow morning', today: tue).pref, TimePref.morning);
    });

    test('unknown requests explain what works', () {
      final r = say('hmm', const []);
      expect(r.summary, contains('Try “Add gym tomorrow for one hour.”'));
    });
  });
}
