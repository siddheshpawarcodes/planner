import 'package:flutter_test/flutter_test.dart';
import 'package:planner_app/data/settings.dart';
import 'package:planner_app/domain/category.dart';
import 'package:planner_app/domain/notifications.dart';
import 'package:planner_app/domain/task.dart';
import 'package:planner_app/features/alarm/alarm_engine.dart';

void main() {
  group('AlarmPrefs', () {
    test('round-trips through Settings JSON, overrides included', () {
      final p = const AlarmPrefs().copyWith(
        style: AlarmStyle.fullScreen,
        look: const AlarmLook(bg: AlarmBg.photo, mediaPath: '/m/a.jpg', blur: 0.4, tint: 0xFFFF7A45, message: 'Go'),
        tonePath: '/t/x.tone',
        toneName: 'Bright',
        fadeSeconds: 30,
        vibrate: false,
        snoozeMinutes: 5,
        slide: true,
      ).withOverride(Category.body, const AlarmLook(lookId: AlarmLookId.embers, font: ClockFont.mono));
      final s = const Settings().copyWith(alarm: p);
      final back = Settings.fromJson(s.toJson()).alarm;
      expect(back, p);
      expect(back.lookFor(Category.body).lookId, AlarmLookId.embers);
      expect(back.lookFor(Category.study).bg, AlarmBg.photo, reason: 'no override: the shared look');
      expect(back.withOverride(Category.body, null).overrides, isEmpty);
    });

    test('old settings without alarm prefs read as the notification style', () {
      final j = const Settings().toJson()..remove('alarm');
      expect(Settings.fromJson(j).alarm.style, AlarmStyle.notification);
      expect(AlarmLook.fromJson(const {'blur': 7}).blur, 1.0, reason: 'clamped');
    });
  });

  group('alarm planning', () {
    final now = DateTime(2026, 9, 29, 19, 40);
    final wed = 20725; // any epoch day; only ids and text matter here
    final tasks = [
      Task.make('a', 'Study polity', Category.study, wed, 1200, 120),
      Task.make('b', 'Exercise', Category.body, wed, 1335, 45),
    ];

    test('alarmsFrom carries the range, the next task and a stable id', () {
      final notes = [
        PlannedNote(4000, NoteKind.alarm, now.add(const Duration(hours: 1)), 'Study polity', '', taskId: 'a'),
        PlannedNote(1000, NoteKind.nextTask, now, 'x', ''),
        PlannedNote(3999, NoteKind.alarm, now, 'Test alarm', '', cat: Category.body),
      ];
      final a = alarmsFrom(notes, tasks);
      expect(a.length, 2);
      expect((a[0].id, a[0].range, a[0].next, a[0].cat), (alarmIdFor('a'), '20:00 → 22:00', 'Then Exercise at 22:15', Category.study));
      expect(alarmIdFor('a'), alarmIdFor('a'));
      expect(alarmIdFor('a'), isNot(alarmIdFor('b')));
      expect(alarmIdFor('a'), greaterThanOrEqualTo(10000));
      expect((a[1].id, a[1].cat, a[1].taskId), (3999, Category.body, null));
      expect(PlannedAlarm.tryParse(a[0].id, '{"bad'), isNull);
    });

    PlannedAlarm alarm(String task, DateTime at) =>
        PlannedAlarm(id: alarmIdFor(task), at: at, title: task, taskId: task);

    test('a sync keeps ringing or snoozed alarms unless their task is finished', () {
      final past = now.subtract(const Duration(minutes: 3));
      final future = now.add(const Duration(hours: 2));
      final held = [
        HeldAlarm(alarmIdFor('a'), past.add(const Duration(minutes: 10)), alarm('a', past), 'k'), // snoozed
        HeldAlarm(alarmIdFor('b'), past, alarm('b', past), 'k'), // ringing, task done
        HeldAlarm(alarmIdFor('c'), future, alarm('c', future), 'k'), // moved away
        HeldAlarm(alarmIdFor('d'), future, alarm('d', future), 'k'), // unchanged
      ];
      final d = alarmDiff(
        held: held,
        plan: [alarm('d', future), alarm('e', future)],
        openTaskIds: {'a', 'c', 'd', 'e'},
        now: now,
        soundKey: 'k',
      );
      expect(d.stop, [alarmIdFor('b'), alarmIdFor('c')]);
      expect(d.set.map((a) => a.taskId), ['e'], reason: 'd is unchanged, a is in flight');

      final again = alarmDiff(held: held, plan: [alarm('d', future)], openTaskIds: {'d'}, now: now, soundKey: 'k2');
      expect(again.set.map((a) => a.taskId), ['d'], reason: 'a new tone or fade sets it again');
    });
  });
}
