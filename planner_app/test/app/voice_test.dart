import 'package:flutter_test/flutter_test.dart';
import 'package:planner_app/app/dev/scenarios.dart';
import 'package:planner_app/app/state/staging.dart';
import 'package:planner_app/app/state/ui_state.dart';
import 'package:planner_app/features/voice/planner_orb.dart';
import 'package:planner_app/features/voice/speech.dart';
import 'package:planner_app/features/voice/voice_controller.dart';

import 'harness.dart';

void main() {
  testWidgets('the three-task request, end to end', (tester) async {
    final h = await pumpScenario(tester, Scenario.tue);
    final voice = h.container.read(voiceControllerProvider.notifier);
    await tester.tap(find.bySemanticsLabel('Talk to Planner'));
    await tester.pump();
    expect(h.container.read(voiceControllerProvider).phase, OrbState.wake);
    await h.settle(1000);
    expect(h.container.read(voiceControllerProvider).phase, OrbState.listening);
    expect(find.text('LISTENING'), findsOneWidget);
    await h.settle(4900); // 150 + 19 words × 215ms + 550
    expect(h.container.read(voiceControllerProvider).phase, OrbState.processing);
    expect(find.text('UNDERSTANDING'), findsOneWidget);
    await h.settle(1200);
    expect(find.text('TOMORROW EVENING'), findsWidgets);
    expect(find.text('2h, 20:00'), findsOneWidget);
    expect(find.text('45m, 22:15'), findsOneWidget);
    expect(find.text('1h, 23:00'), findsOneWidget);
    expect(h.data.tasks.where((t) => t.title == 'Study polity'), isEmpty,
        reason: 'nothing commits before SUCCESS');
    await h.settle(1800);
    // SUCCESS: committed with placement hidden.
    final pol = h.data.tasks.firstWhere((t) => t.title == 'Study polity');
    expect((pol.start, pol.end), (1200, 1320));
    expect(h.container.read(stagingProvider).place[pol.id], isNotNull);
    expect(find.text('SCHEDULED FOR TOMORROW'), findsOneWidget);
    await h.settle(1400); // idle, day switch to Tomorrow
    expect(h.container.read(voiceControllerProvider).open, isFalse);
    expect(h.container.read(todayUiProvider).dayOffset, 1);
    await h.settle(4000); // placement sequence
    expect(h.container.read(stagingProvider).place, isEmpty);
    expect(find.text('This is 50m more than fits before your wind-down.'), findsOneWidget);
    expect(find.text('Move Flutter'), findsOneWidget);
    expect(voice, isNotNull);
    await h.dispose();
  });

  testWidgets('tapping the veil cancels and nothing changes', (tester) async {
    final h = await pumpScenario(tester, Scenario.tue);
    final before = h.data.tasks.length;
    await tester.tap(find.bySemanticsLabel('Talk to Planner'));
    await h.settle(1500);
    await tester.tapAt(const Offset(200, 200));
    await tester.pump();
    expect(find.text('CANCELLED'), findsOneWidget);
    await h.settle(900);
    expect(find.text('Cancelled. Nothing was changed.'), findsOneWidget);
    expect(h.data.tasks.length, before);
    await h.dispose();
  });

  testWidgets('delete always confirms; Keep it changes nothing', (tester) async {
    final h = await pumpScenario(tester, Scenario.wed);
    h.container.read(voiceDebugProvider.notifier).set((v) => v.copyWith(line: 4));
    await tester.tap(find.bySemanticsLabel('Talk to Planner'));
    await h.settle(5000);
    expect(find.text('DELETE THIS TASK?'), findsWidgets);
    expect(find.text('Delete Exercise'), findsOneWidget);
    await tester.tap(find.text('Keep it'));
    await h.settle(600);
    expect(h.data.task('t2')!.deleted, isFalse);
    expect(find.text('Kept. Nothing was changed.'), findsOneWidget);
    await h.dispose();
  });

  testWidgets('microphone denied offers Allow or Type instead', (tester) async {
    final h = await pumpScenario(tester, Scenario.tue);
    h.container.read(voiceDebugProvider.notifier).set((v) => v.copyWith(micAllowed: false));
    await tester.tap(find.bySemanticsLabel('Talk to Planner'));
    await h.settle(1200);
    expect(find.text('MICROPHONE IS OFF'), findsOneWidget);
    expect(find.text('Planner can’t hear you yet.'), findsOneWidget);
    await tester.tap(find.text('Type instead'));
    await h.settle(900);
    expect(find.text('New task'), findsOneWidget);
    await h.dispose();
  });
}
