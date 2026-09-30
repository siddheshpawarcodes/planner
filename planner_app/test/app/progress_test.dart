import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planner_app/app/dev/scenarios.dart';
import 'package:planner_app/app/state/actions.dart';
import 'package:planner_app/app/state/ui_state.dart';
import 'package:planner_app/features/voice/wake_word.dart';

import 'harness.dart';

Future<Harness> openProgress(WidgetTester tester, Scenario k) async {
  final h = await pumpScenario(tester, k);
  h.container.read(actionsProvider).goTab(AppTab.progress);
  await h.settle(2200);
  return h;
}

Future<void> next(WidgetTester tester, Harness h) async {
  await tester.tapAt(const Offset(320, 600));
  await h.settle(2500);
}

void main() {
  testWidgets('Tuesday, first evening: the early-week empty state', (tester) async {
    final h = await openProgress(tester, Scenario.tue);
    expect(find.text('This week'), findsOneWidget);
    expect(find.text('28 Sep → 4 Oct'), findsOneWidget);
    expect(find.text('Your first week has started.'), findsOneWidget);
    expect(find.text('Tell Planner what you want to accomplish. The ribbon fills in as you do it.'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('The weekly review opens on Sunday evening.'), 200);
    expect(find.text('Your rhythm appears here after a few days of use.'), findsOneWidget);
    expect(find.text('Review this week'), findsNothing);
    await h.dispose();
  });

  testWidgets('Sunday 21:00: counts, ribbon day, With work, heat cell', (tester) async {
    final h = await openProgress(tester, Scenario.sunday);
    expect(find.text('10'), findsWidgets);
    expect(find.text('of 10'), findsOneWidget);
    expect(find.text('planned tasks done'), findsOneWidget);
    expect(find.text('Everything you planned landed.'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('12h 15m'), findsOneWidget);
    expect(find.text('days with Planner'), findsOneWidget);
    expect(find.text('Where your week went'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Most productive 20:00 → 22:00, three days out of six'), 200);
    await tester.drag(find.byType(ListView), const Offset(0, 3000));
    await h.settle(600);
    expect(find.text('Where your week went'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Saturday: 6h 45m tracked'));
    await h.settle(700);
    expect(find.text('Saturday, 6h 45m'), findsOneWidget);
    expect(find.text('3h'), findsOneWidget); // Build
    await tester.tap(find.bySemanticsLabel('Monday: 0m tracked'));
    await h.settle(700);
    expect(find.text('Monday, before Planner'), findsOneWidget);
    expect(find.text('Nothing tracked on this day.'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Monday: 0m tracked'));
    await h.settle(700);

    await tester.tap(find.text('With work'));
    await h.settle(700);
    expect(find.text('Work'), findsOneWidget);
    expect(find.text('44h'), findsOneWidget);
    await h.dispose();
  });

  testWidgets('the weekly review: six stages, keys, Plan next week', (tester) async {
    final h = await openProgress(tester, Scenario.sunday);
    await tester.scrollUntilVisible(find.text('Review this week'), 200);
    await tester.tap(find.text('Review this week'));
    await h.settle(1500);
    expect(find.text('Your week, as it happened.'), findsOneWidget);
    expect(h.container.read(wakeGateProvider).onToday, isFalse);

    await next(tester, h);
    expect(find.text('You planned 10 tasks.'), findsOneWidget);
    expect(find.text('You finished 10.'), findsOneWidget);
    expect(find.text('100% completion in your first week. Every square filled in.'), findsOneWidget);

    // Arrow keys move back and forward.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await h.settle(1200);
    expect(find.text('Your week, as it happened.'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await h.settle(1200);

    await next(tester, h);
    expect(find.text('12h 15m'), findsOneWidget);
    expect(find.text('of focused time.'), findsOneWidget);
    await next(tester, h);
    expect(find.text('Some things moved.'), findsOneWidget);
    expect(find.text('Learn Flutter and Exercise found new times'), findsOneWidget);
    await next(tester, h);
    expect(find.text('Your best hours were 20:00 → 22:00.'), findsOneWidget);
    expect(find.text('Study'), findsOneWidget);
    expect(find.text('Saturday'), findsOneWidget);
    await next(tester, h);
    expect(find.text('Coming up.'), findsOneWidget);
    expect(find.text('Nothing carries into next week. Two deadlines are on the way.'), findsOneWidget);
    expect(find.text('UPSC prelims mock'), findsOneWidget);

    await tester.tap(find.text('Plan next week'));
    await h.settle(1200);
    expect(h.container.read(currentTabProvider), AppTab.plan);
    expect(h.container.read(planUiProvider).seg, PlanSeg.upcoming);
    expect(find.text('Next week starts with 2 deadlines.'), findsOneWidget);
    await h.dispose();
  });

  testWidgets('the review closes with Esc and the close button', (tester) async {
    final h = await openProgress(tester, Scenario.sunday);
    h.container.read(actionsProvider).openReview();
    await h.settle(1200);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle(800);
    expect(find.text('Your week, as it happened.'), findsNothing);
    h.container.read(actionsProvider).openReview();
    await h.settle(1200);
    await tester.tap(find.bySemanticsLabel('Close review'));
    await h.settle(800);
    expect(find.text('Your week, as it happened.'), findsNothing);
    expect(h.container.read(currentTabProvider), AppTab.progress);
    await h.dispose();
  });
}
