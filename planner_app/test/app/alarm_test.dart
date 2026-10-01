import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planner_app/app/dev/scenarios.dart';
import 'package:planner_app/app/state/actions.dart';
import 'package:planner_app/app/state/ui_state.dart';
import 'package:planner_app/data/settings.dart';
import 'package:planner_app/domain/category.dart';
import 'package:planner_app/domain/notifications.dart';
import 'package:planner_app/features/alarm/alarm_customise_page.dart';
import 'package:planner_app/features/alarm/alarm_engine.dart';
import 'package:planner_app/features/alarm/alarm_platform.dart';
import 'package:planner_app/features/notifications/notification_service.dart';

import 'harness.dart';

class _FakeMedia extends AlarmMedia {
  const _FakeMedia();
  @override
  Future<String?> pick({required bool video}) async => video ? '/m/clip.mp4' : '/m/photo.jpg';
  @override
  Future<void> prune(AlarmPrefs p) async {}
}

void main() {
  late NoAlarmEngine engine;
  late NoAlarmPlatform platform;

  Future<Harness> pump(WidgetTester tester, Scenario k, {AlarmPrefs prefs = const AlarmPrefs(style: AlarmStyle.fullScreen), List extra = const []}) {
    engine = NoAlarmEngine(available: true);
    platform = NoAlarmPlatform(toneList: const [AlarmTone('Bright', 'content://tones/bright')]);
    return pumpScenario(tester, k,
        edit: (d) => d.copyWith(settings: d.settings.copyWith(alarm: prefs)),
        overrides: [
          alarmEngineProvider.overrideWithValue(engine),
          alarmPlatformProvider.overrideWithValue(platform),
          alarmMediaProvider.overrideWithValue(const _FakeMedia()),
          ...extra,
        ]);
  }

  PlannedAlarm ringFor(Harness h, String id) {
    final t = h.data.task(id)!;
    return alarmsFrom([
      PlannedNote(0, NoteKind.alarm, DateTime(2026, 9, 30, 20), t.title, '', taskId: id),
    ], h.data.tasks).single;
  }

  testWidgets('a ringing alarm covers everything; Done completes the task and closes it', (tester) async {
    final h = await pump(tester, Scenario.wed); // Wed 21:40, Study polity running
    final a = ringFor(h, 't1');
    engine.ring(a);
    await h.settle(800);
    expect(find.text('TASK ALARM'), findsOneWidget);
    expect(find.text('20:00 → 22:00'), findsOneWidget);
    expect(find.text('Then Exercise at 22:15'), findsOneWidget);
    expect(platform.overLock, 1);

    await tester.tap(find.bySemanticsLabel('Done, mark Study polity complete'));
    await h.settle(800);
    expect(engine.stopped, [a.id]);
    expect(h.data.task('t1')!.done, isTrue);
    expect(platform.released, greaterThanOrEqualTo(1));
    expect(find.text('TASK ALARM'), findsNothing);
    expect(find.text('Study polity done early. 20 min back in your evening.'), findsOneWidget);
    await h.dispose();
  });

  testWidgets('Snooze uses the chosen length; Start now opens the task', (tester) async {
    final h = await pump(tester, Scenario.wed,
        prefs: const AlarmPrefs(style: AlarmStyle.fullScreen, snoozeMinutes: 5));
    final ex = ringFor(h, 't2');
    engine.ring(ex);
    await h.settle(800);
    await tester.tap(find.text('Snooze 5 min'));
    await h.settle(800);
    expect(engine.snoozed[ex.id], const Duration(minutes: 5));
    expect(find.text('TASK ALARM'), findsNothing);
    expect(h.data.task('t2')!.done, isFalse);

    engine.ring(ex);
    await h.settle(800);
    await tester.tap(find.text('Start now'));
    await h.settle(900);
    expect(platform.stayed, 1);
    expect(engine.stopped, [ex.id]);
    expect(h.container.read(sheetProvider)!.kind, SheetKind.detail);
    expect(h.container.read(sheetProvider)!.taskId, 't2');
    await h.dispose();
  });

  testWidgets('slide to confirm: a short slide springs back, a long one is Done', (tester) async {
    final h = await pump(tester, Scenario.wed, prefs: const AlarmPrefs(style: AlarmStyle.fullScreen, slide: true));
    final a = ringFor(h, 't1');
    engine.ring(a);
    await h.settle(800);
    expect(find.text('Done'), findsNothing);
    final track = find.bySemanticsLabel('Slide right for Done, left to snooze');
    await tester.drag(track, const Offset(40, 0));
    await h.settle(600);
    expect(engine.stopped, isEmpty);
    await tester.drag(track, const Offset(260, 0));
    await h.settle(800);
    expect(engine.stopped, [a.id]);
    expect(h.data.task('t1')!.done, isTrue);
    await h.dispose();
  });

  testWidgets('full-screen style sends task alarms to the engine, not to notifications', (tester) async {
    final notes = NoNotifications();
    final h = await pump(tester, Scenario.tue, extra: [notificationServiceProvider.overrideWithValue(notes)]);
    h.container.read(testAlarmProvider.notifier).set(DateTime.now().add(const Duration(hours: 1)), cat: Category.body);
    await h.settle(1500);
    expect(engine.held.keys, contains(3999));
    expect(engine.held[3999]!.$1.cat, Category.body);
    expect(notes.scheduled.where((n) => n.kind == NoteKind.alarm), isEmpty);

    // Back to the notification style: the engine lets go of everything.
    final s = h.data.settings;
    await h.container.read(actionsProvider).store.setSettings(
        s.copyWith(alarm: s.alarm.copyWith(style: AlarmStyle.notification)));
    await h.settle(1500);
    expect(engine.held, isEmpty);
    expect(notes.scheduled.where((n) => n.kind == NoteKind.alarm).map((n) => n.id), [3999]);
    await h.dispose();
  });

  testWidgets('Settings › Alarm style › Customise: looks, a category of its own, tone', (tester) async {
    final h = await pump(tester, Scenario.tue, prefs: const AlarmPrefs());
    h.container.read(actionsProvider).goTab(AppTab.settings);
    await h.settle(800);
    expect(find.text('Customise alarm screen'), findsNothing);
    await tester.tap(find.text('Full screen'));
    await h.settle(400);
    expect(h.data.settings.alarm.style, AlarmStyle.fullScreen);
    await tester.tap(find.text('Customise alarm screen'));
    await h.settle(900);
    expect(find.text('Alarm screen'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Stars look'));
    await h.settle(300);
    expect(h.data.settings.alarm.look.lookId, AlarmLookId.stars);

    // Body gets its own look; the shared one is untouched.
    await tester.tap(find.text('Body'));
    await h.settle(300);
    await tester.tap(find.text('Give Body its own look'));
    await h.settle(300);
    await tester.tap(find.text('Photo or GIF'));
    await h.settle(300);
    var p = h.data.settings.alarm;
    expect((p.lookFor(Category.body).bg, p.lookFor(Category.body).mediaPath), (AlarmBg.photo, '/m/photo.jpg'));
    expect(p.look.bg, AlarmBg.look);

    await tester.tap(find.text('Ring a test'));
    await h.settle(300);
    expect(h.container.read(testAlarmProvider)!.$2, Category.body);

    await tester.scrollUntilVisible(find.text('Alarm tone'), 200,
        scrollable: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).last);
    await tester.tap(find.bySemanticsLabel('Alarm tone, Phone default'));
    await h.settle(600);
    await tester.tap(find.text('Bright'));
    await h.settle(200);
    expect(platform.previewing, 'content://tones/bright');
    await tester.tap(find.text('Use Bright'));
    await h.settle(600);
    p = h.data.settings.alarm;
    expect((p.toneName, p.tonePath), ('Bright', '/tones/Bright.tone'));
    expect(platform.previewing, isNull, reason: 'the preview stops when the picker closes');
    await h.dispose();
  });
}
