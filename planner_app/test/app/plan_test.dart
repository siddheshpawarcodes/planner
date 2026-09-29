import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planner_app/app/dev/scenarios.dart';
import 'package:planner_app/app/state/actions.dart';
import 'package:planner_app/app/state/ui_state.dart';
import 'package:planner_app/features/plan/plan_board.dart';
import 'package:planner_app/features/plan/plan_page.dart';

import 'harness.dart';

Future<Harness> pumpWeek(WidgetTester tester, {int selOffset = 3}) async {
  final h = await pumpScenario(tester, Scenario.week);
  final mon = h.data.installedDay! - 1;
  h.container.read(planUiProvider.notifier).set((_) => PlanUi(seg: PlanSeg.week, weekSel: mon + selOffset));
  h.container.read(actionsProvider).goTab(AppTab.plan);
  await h.settle(1200);
  return h;
}

void main() {
  testWidgets('Week: title, range and the expanded Thursday', (tester) async {
    final h = await pumpWeek(tester);
    expect(find.text('This week'), findsOneWidget);
    expect(find.text('28 Sep → 4 Oct'), findsOneWidget);
    expect(find.text('Thu 1'), findsOneWidget);
    expect(find.text('Thursday 1 October'), findsOneWidget);
    expect(find.textContaining('planned of 3h 10m realistic'), findsOneWidget);
    expect(find.text('Learn Flutter'), findsOneWidget);
    await h.dispose();
  });

  testWidgets('drag Revise polity notes to Sat 10:00: ripple, scan, note', (tester) async {
    final h = await pumpWeek(tester, selOffset: 4); // Friday expanded
    final origin = tester.getTopLeft(find.byType(PlanBoard));
    // Fri column x 146, block at 20:00 → y = 44 + 840 × 0.4 = 380.
    final start = origin + const Offset(146 + 3 + 20, 380 + 10);
    final g = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 320)); // long press 250ms
    for (var i = 1; i <= 8; i++) {
      await g.moveTo(start + Offset(156 * i / 8, -240 * i / 8));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.text('Sat 3 10:00 → 11:30'), findsOneWidget, reason: 'the ghost readout');
    await g.up();
    await tester.pump();
    final rev = h.data.task('t4')!;
    final sat = h.data.installedDay! + 4;
    expect((rev.day, rev.start, rev.end), (sat, 600, 690));
    expect(rev.movedCount, 1);
    expect(h.data.task('t6')!.start, 735, reason: 'neighbours reflowed');
    await h.settle(600);
    expect(
        find.text('Revise polity notes moved to Sat 3 Oct, 10:00. 3 blocks made room. '
            'Saturday is now 2h 45m over what fits.'),
        findsOneWidget);

    // Undo puts every block back.
    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(h.data.task('t4')!.day, sat - 1);
    expect(h.data.task('t6')!.start, 660);
    await h.dispose();
  });

  testWidgets('an overloaded day offers Move one', (tester) async {
    final h = await pumpWeek(tester, selOffset: 5);
    final sat = h.data.installedDay! + 4;
    await h.container.read(actionsProvider).dropOnBoard('t4', sat, 600);
    await h.settle(800);
    expect(find.text('Saturday runs 2h 45m past what fits. Move one block to a lighter day?'),
        findsOneWidget);
    await tester.ensureVisible(find.text('Move one'));
    await tester.tap(find.text('Move one'));
    await tester.pump();
    final wmm = h.data.task('t5')!;
    expect((wmm.day, wmm.start), (sat + 1, 735));
    await h.settle(600);
    expect(find.text('WMM side project moved to Sun 4 Oct, 12:15. Saturday fits again.'), findsOneWidget);
    await h.dispose();
  });

  testWidgets('Today and Tomorrow zooms show the inbox; Upcoming lists', (tester) async {
    final h = await pumpWeek(tester);
    await tester.tap(find.descendant(of: find.byType(PlanPage), matching: find.text('Tomorrow')).first);
    await h.settle(800);
    expect(find.text('Friday 2 October'), findsWidgets);
    expect(find.text('Unscheduled'), findsWidgets);
    expect(find.text('Journal'), findsWidgets);
    await tester.tap(find.text('Upcoming'));
    await h.settle(800);
    expect(find.text('Deadlines'), findsOneWidget);
    expect(find.text('WMM report'), findsOneWidget);
    expect(find.text('Due 18:00'), findsOneWidget);
    expect(find.text('3 study blocks planned before it'), findsOneWidget);
    expect(find.text('Repeats'), findsOneWidget);
    expect(find.text('Every day, 19:00 → 20:00'), findsOneWidget);
    await tester.tap(find.text('Fit in').last);
    await tester.pump();
    final j = h.data.task('i4')!;
    expect((j.day, j.start), (h.data.installedDay! + 2, 1260));
    await h.settle(600);
    expect(find.text('Journal fits today, 21:00.'), findsOneWidget);
    await h.dispose();
  });
}
