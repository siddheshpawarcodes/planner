import 'package:flutter_test/flutter_test.dart';
import 'package:planner_app/app/dev/scenarios.dart';
import 'package:planner_app/domain/category.dart';
import 'package:planner_app/domain/progress.dart';
import 'package:planner_app/domain/task.dart';
import 'package:planner_app/domain/time.dart';

import 'fixtures.dart';

WeekProgress scenario(Scenario k) {
  final s = buildScenario(k, now: DateTime(2026, 9, 28));
  return weekProgress(
      tasks: s.data.tasks,
      routine: s.data.routine,
      today: dayOf(s.clock),
      now: minuteOf(s.clock),
      installedDay: s.data.installedDay);
}

void main() {
  group('Sunday 21:00, the week as it happened', () {
    final p = scenario(Scenario.sunday);

    test('counts: planned, done, days with Planner, focused', () {
      expect((p.plannedCount, p.doneCount, p.percent), (10, 10, 100));
      expect(p.daysWithPlanner, 6); // installed Tuesday
      expect(p.beforePlanner(0), isTrue);
      expect(dur(p.focusedMinutes), '12h 15m');
      expect(p.rescheduled.map((t) => t.title), ['Learn Flutter', 'Exercise']);
      expect(p.skipped.map((t) => t.title), ['Flutter: state management', 'Read fiction']);
      expect(p.carried, isEmpty);
    });

    test('completed hours per category and day, and the planned envelope', () {
      expect(p.completed[Category.study], [0, 0, 100, 45, 90, 120, 120]);
      expect(p.completed[Category.build], [0, 0, 0, 60, 0, 180, 0]);
      expect(p.completed[Category.work], [0, 660, 660, 660, 660, 0, 0]);
      expect(p.completed[Category.rest], [0, 60, 60, 60, 60, 60, 60]); // dinner
      expect(p.planned, [0, 60, 160, 165, 180, 405, 200]);
      expect(p.envelope(1, withWork: true), 720);
      expect(p.dayTotal(5, withWork: false), 405);
      expect(p.totals(withWork: false).first, (Category.study, 475));
      expect(p.mostActive, (Category.study, 475));
      expect(p.biggestDay, (5, 405));
    });

    test('heatmap from actual completion times and the best window', () {
      final b = p.best!;
      expect((fmt(b.start), fmt(b.end), b.days), ('20:00', '22:00', 3));
      expect(heatSummary(p), 'Most productive 20:00 → 22:00, three days out of six');
      // Wednesday: Study polity 20:00 → 21:40 (done early).
      expect(p.heat[2].sublist(28, 32), [30, 30, 30, 10]);
      expect(heatCellText(p, 2, 31), 'Wed 21:30 → 22:00: 10m focused');
    });

    test('review copy', () {
      expect(reviewIntro(p), startsWith('Six days with Planner.'));
      expect(reviewCompletion(p, firstWeek: true), '100% completion in your first week. Every square filled in.');
      final m = reviewMoves(p);
      expect(m[0], ('Rescheduled', 2, 'Learn Flutter and Exercise found new times'));
      expect(m[1], ('Skipped', 2, 'Flutter: state management and Read fiction'));
      expect(m[2], ('Carried forward', 0, 'Nothing carries over'));
      expect(reviewBestHours(p),
          ('Your best hours were 20:00 → 22:00.', 'Three evenings out of six. Planner will put demanding work there first.'));
      expect(progressSubline(p, weekDone: true), 'Everything you planned landed.');
    });
  });

  group('Wednesday 21:40, mid-week', () {
    final p = scenario(Scenario.wed);

    test('only days up to today count, and passed fixed time is lived', () {
      expect((p.plannedCount, p.doneCount), (2, 0));
      expect(p.daysWithPlanner, 2);
      expect(p.completed[Category.work]!.sublist(0, 4), [0, 660, 660, 0]);
      expect(p.planned.sublist(0, 4), [0, 60, 225, 0]);
      expect(heatSummary(p), 'Your rhythm appears here after a few days of use.');
      expect(progressSubline(p, weekDone: false), 'The ribbon fills in as the week happens.');
    });

    test('today counts fixed time only up to now', () {
      final q = weekProgress(tasks: const [], routine: routine, today: wed, now: 1170, installedDay: mon);
      expect(q.completed[Category.rest]![2], 30); // dinner 19:00 → 19:30 so far
      expect(q.planned[2], 60);
    });
  });

  test('missed tasks carry forward; skipped count only when set', () {
    final all = [
      Task.make('a', 'Exercise', Category.body, tue, 1335, 45),
      Task.make('b', 'Read', Category.self, tue, 1200, 30).copyWith(skipped: true),
      Task.make('c', 'Polity', Category.study, wed, 1230, 120).copyWith(done: true),
    ];
    final p = weekProgress(tasks: all, routine: routine, today: wed, now: 1300, installedDay: mon);
    expect(p.carried.map((t) => t.title), ['Exercise']);
    expect(p.plannedCount, 2);
    expect(weekProgress(tasks: all, routine: routine, today: wed, now: 1300, countSkippedAsMissed: true).plannedCount, 3);
    expect(p.heat[2].sublist(29, 33), [30, 30, 30, 30]);
    expect(heatLevel(p.heat[2][29]), 4);
    expect(progressSubline(p, weekDone: true), 'Most of what you planned landed.');
  });

  test('copy helpers', () {
    expect(nameList(['A']), 'A');
    expect(nameList(['A', 'B', 'C', 'D']), 'A, B and 2 more');
    expect(reviewAhead(1, 2), 'One task carries into next week. Two deadlines are on the way.');
    expect(reviewAhead(0, 0), 'Nothing carries into next week. No deadlines are on the way.');
    expect(planNextNote(1, 2), 'Next week starts with 1 carried-forward task and 2 deadlines.');
    expect(planNextNote(0, 0), 'Next week starts clear.');
    expect([0, 5, 8, 9, 15, 22, 23].map(heatLevel), [0, 1, 1, 2, 2, 3, 4]);
    expect(reviewAvailable(sun, 1080), isTrue);
    expect(reviewAvailable(sun, 1000), isFalse);
    expect(reviewAvailable(sat, 1260), isFalse);
  });
}
