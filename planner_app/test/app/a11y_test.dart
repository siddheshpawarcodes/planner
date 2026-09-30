import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planner_app/app/dev/scenarios.dart';
import 'package:planner_app/app/state/actions.dart';
import 'package:planner_app/app/state/staging.dart';
import 'package:planner_app/app/state/ui_state.dart';
import 'package:planner_app/data/settings.dart';
import 'package:planner_app/features/voice/voice_controller.dart';

import 'harness.dart';

/// README 9 and 3.5: every screen at 1.3× text with reduced motion. Rows grow
/// rather than truncate, so any overflow fails the test.
Future<Harness> big(WidgetTester tester, Scenario k, {Size size = const Size(400, 860)}) async {
  tester.platformDispatcher.textScaleFactorTestValue = 1.3;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  return pumpScenario(tester, k,
      size: size, edit: (d) => d.copyWith(settings: d.settings.copyWith(motion: MotionChoice.reduced)));
}

void main() {
  testWidgets('Today, Dial, sheets and voice at 1.3×', (tester) async {
    final h = await big(tester, Scenario.wed);
    final act = h.container.read(actionsProvider);
    expect(find.text('Wednesday 30 September'), findsOneWidget);
    await tester.tap(find.text('Dial'));
    await h.settle(600);
    await tester.tap(find.text('Strip'));
    await h.settle(600);
    final id = h.data.tasks.firstWhere((t) => t.title == 'Study polity').id;
    act.openBlock(id);
    await h.settle(600);
    act.closeSheet();
    await h.settle(400);
    act.openDecision(id, reschedule: true);
    await h.settle(600);
    act.closeSheet();
    await h.settle(400);
    act.openCreate();
    await h.settle(600);
    act.closeSheet();
    await h.settle(400);
    h.container.read(voiceControllerProvider.notifier).tapOrb();
    await h.settle(6000);
    h.container.read(voiceControllerProvider.notifier).close();
    await h.settle(400);
    await h.dispose();
  });

  testWidgets('Plan zooms and Upcoming at 1.3×', (tester) async {
    final h = await big(tester, Scenario.week);
    final act = h.container.read(actionsProvider);
    act.goTab(AppTab.plan);
    await h.settle(600);
    for (final seg in PlanSeg.values) {
      act.setSeg(seg);
      await h.settle(600);
    }
    await h.dispose();
  });

  testWidgets('Progress, the review and Settings at 1.3×', (tester) async {
    final h = await big(tester, Scenario.sunday);
    final act = h.container.read(actionsProvider);
    act.goTab(AppTab.progress);
    await h.settle(1500);
    await tester.drag(find.byType(ListView).first, const Offset(0, -2000));
    await h.settle(400);
    act.openReview();
    await h.settle(1200);
    for (var i = 0; i < 5; i++) {
      await tester.tapAt(const Offset(320, 700));
      await h.settle(2600);
    }
    expect(find.text('Coming up.'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await h.settle(800);
    act.goTab(AppTab.settings);
    await h.settle(800);
    act.openDrivePage();
    await h.settle(800);
    await h.dispose();
  });

  testWidgets('onboarding at 1.3× on a small phone', (tester) async {
    final h = await big(tester, Scenario.onboard, size: const Size(360, 640));
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('Continue'));
      await h.settle(400);
    }
    await tester.scrollUntilVisible(find.text('Add your own'), 100);
    await tester.tap(find.text('Add your own'));
    await h.settle(300);
    await tester.tap(find.text('Build my rhythm'));
    await h.settle(1500);
    expect(find.text('Your rhythm is ready.'), findsOneWidget);
    await h.dispose();
  });

  testWidgets('tablet at 1.3×', (tester) async {
    final h = await big(tester, Scenario.week, size: const Size(834, 1194));
    h.container.read(actionsProvider).goTab(AppTab.progress);
    await h.settle(1500);
    h.container.read(actionsProvider).goTab(AppTab.settings);
    await h.settle(800);
    await h.dispose();
  });

  // README 3.4 and 9: 44 × 44 targets, a label on everything tappable, AA
  // text contrast. The Plan board's time-proportional blocks and 26px
  // collapsed columns are the one exception (they have custom actions,
  // keyboard focus, and the same tasks at full size on Today).
  for (final tab in [AppTab.today, AppTab.plan, AppTab.progress, AppTab.settings]) {
    testWidgets('guidelines: $tab', (tester) async {
      final h = await pumpScenario(tester, Scenario.wed);
      h.container.read(actionsProvider).goTab(tab);
      await h.settle(1800);
      if (tab != AppTab.plan) {
        await expectLater(tester, meetsGuideline(const MinimumTapTargetGuideline(size: Size(44, 44), link: 'README 3.4')));
      }
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      await h.dispose();
    });
  }

  testWidgets('reduced motion: placement appears in place, no introduction', (tester) async {
    final h = await big(tester, Scenario.wed);
    final seen = <PlaceStage>{};
    h.container.listen(stagingProvider, (_, s) => seen.addAll(s.place.values), fireImmediately: true);
    final id = h.data.tasks.firstWhere((t) => t.title == 'Exercise').id;
    h.container.read(actionsProvider).runPlacement([id]);
    await h.settle(1500);
    expect(seen, contains(PlaceStage.placed));
    expect(seen, isNot(contains(PlaceStage.staged)));
    await h.dispose();
  });
}
