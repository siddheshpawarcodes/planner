import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planner_app/app/dev/scenarios.dart';
import 'package:planner_app/app/state/ui_state.dart';
import 'package:planner_app/widgets/side_nav.dart';
import 'package:planner_app/widgets/task_focus.dart';

import 'harness.dart';

void main() {
  testWidgets('tablet: rail, the Today pane and the Plan board side by side', (tester) async {
    final h = await pumpScenario(tester, Scenario.tue, size: const Size(1194, 834));
    expect(find.byType(NavRail), findsOneWidget);
    expect(find.text('No plans yet.'), findsOneWidget); // Today pane
    expect(find.text('This week'), findsOneWidget); // Plan board beside it
    expect(find.text('Strip'), findsNothing, reason: 'the Today pane is strip only');
    await tester.tap(find.bySemanticsLabel('Progress'));
    await h.settle(900);
    expect(h.container.read(currentTabProvider), AppTab.progress);
    expect(find.text('No plans yet.'), findsOneWidget, reason: 'Today stays visible');
    await h.dispose();
  });

  testWidgets('desktop: sidebar with key hints, week planner, Today rail', (tester) async {
    final h = await pumpScenario(tester, Scenario.week, size: const Size(1440, 900));
    expect(find.byType(Sidebar), findsOneWidget);
    expect(find.text('Talk to Planner'), findsWidgets); // sidebar card and key legend
    expect(find.text('Planner'), findsOneWidget);
    expect(find.textContaining('planned of', findRichText: true), findsWidgets);
    await h.dispose();
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('keys: N opens the sheet, Esc closes it, ? lists shortcuts, T P G switch', (tester) async {
    final h = await pumpScenario(tester, Scenario.tue);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await h.settle(800);
    expect(find.text('What do you need to do?'), findsOneWidget);
    // Typing in the title never triggers shortcuts.
    await tester.enterText(find.byType(TextField).first, 'Plan');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pump();
    expect(h.container.read(currentTabProvider), AppTab.today);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle(800);
    expect(h.container.read(sheetProvider), isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await h.settle(700);
    expect(h.container.read(currentTabProvider), AppTab.plan);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
    await h.settle(700);
    expect(h.container.read(currentTabProvider), AppTab.progress);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await h.settle(700);
    expect(h.container.read(currentTabProvider), AppTab.today);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await h.settle(500);
    expect(h.container.read(todayUiProvider).dayOffset, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await h.settle(500);
    expect(h.container.read(todayUiProvider).dayOffset, 0);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await h.settle(400);
    expect(find.text('Keyboard shortcuts'), findsOneWidget);
    expect(find.text('Move a day'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle(400);
    expect(find.text('Keyboard shortcuts'), findsNothing);
    await h.dispose();
  });

  testWidgets('a focused block: Space completes, Ctrl Z undoes, Alt ↓ moves 15 min', (tester) async {
    final h = await pumpScenario(tester, Scenario.wed);
    Focus.of(tester.element(find.descendant(of: find.byType(TaskFocus).first, matching: find.byType(DecoratedBox)).first))
        .requestFocus();
    await tester.pump();
    final id = h.data.tasks.firstWhere((t) => t.title == 'Study polity').id;
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(h.data.task(id)!.done, isTrue);
    await h.settle(400);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(h.data.task(id)!.done, isFalse);
    await h.settle(600);

    final ex = h.data.tasks.firstWhere((t) => t.title == 'Exercise');
    await tester.tap(find.bySemanticsLabel(RegExp('^Exercise')).first, warnIfMissed: false);
    await h.settle(800);
    h.container.read(sheetProvider.notifier).close();
    await h.settle(800);
    final exFocus = find.byWidgetPredicate((w) => w is TaskFocus && w.taskId == ex.id);
    Focus.of(tester.element(find.descendant(of: exFocus, matching: find.byType(DecoratedBox)).first)).requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    expect(h.data.task(ex.id)!.start, ex.start! + 15);
    await h.dispose();
  });
}
