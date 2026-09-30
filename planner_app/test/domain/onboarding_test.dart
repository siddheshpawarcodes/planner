import 'package:flutter_test/flutter_test.dart';
import 'package:planner_app/domain/capacity.dart';
import 'package:planner_app/domain/category.dart';
import 'package:planner_app/domain/onboarding.dart';
import 'package:planner_app/domain/routine.dart';
import 'package:planner_app/domain/scheduler.dart';
import 'package:planner_app/domain/task.dart';

import 'fixtures.dart';

void main() {
  group('onboarding draft', () {
    test('defaults are the README routine: 07:00, 08:00-19:00, 00:00, dinner on', () {
      const d = OnboardingDraft();
      final r = d.toRoutine();
      expect((r.wake, r.workStart, r.workEnd, r.sleep), (420, 480, 1140, 1440));
      expect(r.commitments.where((c) => c.on).map((c) => c.title), ['Dinner']);
      expect(d.field, ObField.wake);
      expect(d.value, 420);
    });

    test('−/+ move by 15 minutes and clamp to 04:00-12:00 for wake', () {
      var d = const OnboardingDraft();
      d = d.nudge(15);
      expect(d.wake, 435);
      d = d.nudge(-15).nudge(-15);
      expect(d.wake, 405);
      expect(d.set(100).wake, 240);
      expect(d.set(900).wake, 720);
    });

    test('a later wake pushes work start, work end and sleep forward', () {
      final d = const OnboardingDraft().set(720);
      expect(d.workStart, 735);
      expect(d.workEnd, 1140); // still 1h after work start
      final d2 = const OnboardingDraft(step: 1).set(840);
      expect(d2.workStart, 840);
      expect(d2.workEnd, 1140);
      final d3 = const OnboardingDraft(step: 2).set(1380);
      expect(d3.workEnd, 1380);
      expect(d3.sleep, 1440);
    });

    test('sleep is at least 20:00 and at most 02:00', () {
      const d = OnboardingDraft(step: 3);
      expect(d.set(600).sleep, 1200);
      expect(d.set(2000).sleep, 1560);
    });

    test('the ruler moves 2 px per minute and snaps to 5 minutes', () {
      const d = OnboardingDraft();
      // Dragging left moves later.
      expect(d.drag(420, -60).wake, 450);
      expect(d.drag(420, 23).wake, 410); // 420 − 11.5 → 408.5 → 410
      expect(d.drag(420, 36).wake, 400);
    });

    test('"I don\'t work fixed hours" skips the work-end question, both ways', () {
      var d = const OnboardingDraft().next();
      expect(d.step, 1);
      d = d.toggleNoWork().next();
      expect(d.step, 3);
      expect(d.back().step, 1);
      expect(d.toRoutine().noFixedWork, isTrue);
    });

    test('steps run 0 → 4 → build; back is only offered on questions 2-5', () {
      var d = const OnboardingDraft();
      expect(d.canBack, isFalse);
      for (var i = 0; i < 4; i++) {
        d = d.next();
      }
      expect(d.step, kObCommitStep);
      expect(d.canBack, isTrue);
      d = d.next();
      expect(d.step, kObBuildStep);
      expect(d.canBack, isFalse);
      expect(d.back().step, kObBuildStep);
    });

    test('commitments toggle, and Add your own infers the category', () {
      var d = const OnboardingDraft(step: 4).flip('gym');
      expect(d.commitments.firstWhere((c) => c.id == 'gym').on, isTrue);
      d = d.openCustom().editCustom((c) => c.copyWith(title: '  ', at: 1260));
      expect(d.addCustom('cu1').commitments.length, 3); // blank title: nothing
      d = d.editCustom((c) => c.copyWith(title: 'Evening walk', length: 60, days: DayRule.weekdays)).addCustom('cu1');
      final c = d.commitments.last;
      expect(d.custom, isNull);
      expect((c.title, c.cat, c.start, c.end, c.on), ('Evening walk', Category.body, 1260, 1320, true));
      expect(c.label, 'Weekdays, 21:00 → 22:00');
    });

    test('Edit routine starts from the current routine', () {
      const r = Routine(wake: 390, workStart: 540, workEnd: 1080, sleep: 1410, noFixedWork: true);
      final d = OnboardingDraft.from(r);
      expect((d.step, d.wake, d.workStart, d.workEnd, d.sleep, d.noWork), (0, 390, 540, 1080, 1410, true));
    });
  });

  group('rhythm', () {
    test('acceptance: the weekday realistic evening is 3h 10m, weekends 6h', () {
      const d = OnboardingDraft();
      final r = d.toRoutine();
      expect(capOf(wed, r, const [], 0).realistic, 190);
      expect(rhythmCopy(r, tue), '3h 10m of realistic time every weekday evening. Up to 6h on weekends.');
    });

    test('the assembly builds the first weekday', () {
      expect(firstWeekday(tue), tue);
      expect(firstWeekday(sat), mon + 7);
      expect(firstSaturday(tue), sat);
      expect(firstSaturday(sat), sat);
      expect(firstSaturday(sun), sat + 7);
    });
  });

  group('reflowForRoutine', () {
    List<Task> week() => [
          Task.make('p', 'Study polity', Category.study, wed, 1200, 120),
          Task.make('e', 'Exercise', Category.body, wed, 1335, 45),
          Task.make('d', 'Read', Category.self, tue, 1200, 30).copyWith(done: true),
          Task.make('x', 'Early read', Category.self, tue, 1170, 20),
          Task.make('i', 'Journal', Category.self, null, null, 15),
        ];

    test('an unchanged routine moves nothing', () {
      final all = week();
      expect(identical(reflowForRoutine(all, routine, tue, 1180), all), isTrue);
    });

    test('a later dinner pushes the evening forward in order', () {
      final r = routine.copyWith(commitments: [
        for (final c in routine.commitments) c.id == 'dinner' ? c.copyWith(start: 1200, end: 1260) : c,
      ]);
      final all = week();
      final out = reflowForRoutine(all, r, tue, 1180);
      Task t(String id) => out.firstWhere((x) => x.id == id);
      expect((t('p').start, t('p').end), (1260, 1380)); // 21:00 → 23:00
      expect((t('e').start, t('e').end), (1395, 1440)); // after the 15 min break
      // Done, already started (today) and unscheduled tasks stay put.
      expect(identical(t('d'), all[2]), isTrue);
      expect(identical(t('x'), all[3]), isTrue);
      expect(identical(t('i'), all[4]), isTrue);
    });

    test('a later wake moves a morning task out of Getting ready', () {
      final all = [Task.make('m', 'Run', Category.body, sat, 480, 30)];
      final out = reflowForRoutine(all, routine.copyWith(wake: 510), tue, 1180);
      expect(out.single.start, 570); // wake 08:30 + 60 min getting ready
    });
  });
}
