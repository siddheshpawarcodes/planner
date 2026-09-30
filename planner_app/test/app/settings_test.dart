import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planner_app/app/dev/scenarios.dart';
import 'package:planner_app/app/state/actions.dart';
import 'package:planner_app/app/state/ui_state.dart';
import 'package:planner_app/data/settings.dart';

import 'harness.dart';

Future<Harness> openSettings(WidgetTester tester) async {
  final h = await pumpScenario(tester, Scenario.tue);
  h.container.read(actionsProvider).goTab(AppTab.plan);
  await h.settle(600);
  h.container.read(actionsProvider).goTab(AppTab.settings);
  await h.settle(800);
  return h;
}

void main() {
  testWidgets('switches and choices write settings; close returns to the last tab', (tester) async {
    final h = await openSettings(tester);
    expect(find.text('Notifications'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Next task'));
    await tester.pump();
    expect(h.data.settings.notifyNext, isFalse);
    expect(h.repo.data.settings.notifyNext, isFalse);
    await tester.tap(find.bySemanticsLabel('Wake phrase'));
    await tester.pump();
    expect(h.data.settings.wakeWord, isFalse);
    await tester.scrollUntilVisible(find.text('Dark'), 300);
    await tester.tap(find.text('Dark'));
    await h.settle(600);
    expect(h.data.settings.theme, ThemeChoice.dark);
    await tester.tap(find.text('Reduced'));
    await tester.pump();
    expect(h.data.settings.motion, MotionChoice.reduced);
    await tester.drag(find.byType(ListView).last, const Offset(0, 3000));
    await h.settle(400);
    await tester.tap(find.bySemanticsLabel('Close settings'));
    await h.settle(800);
    expect(h.container.read(currentTabProvider), AppTab.plan);
    await h.dispose();
  });

  testWidgets('Delete all data needs a second tap, then onboarding opens', (tester) async {
    final h = await openSettings(tester);
    await tester.scrollUntilVisible(find.text('Delete all data'), 300);
    await tester.tap(find.text('Delete all data'));
    await tester.pump();
    expect(find.text('Tap again to erase everything on this phone'), findsOneWidget);
    expect(h.data.tasks, isNotEmpty);
    await tester.tap(find.text('Tap again to erase everything on this phone'));
    await h.settle(1200);
    expect(h.data.tasks, isEmpty);
    expect(h.data.onboarded, isFalse);
    expect(find.text('When do you wake up?'), findsOneWidget);
    await h.dispose();
  });

  testWidgets('the first tap disarms after 4 seconds', (tester) async {
    final h = await openSettings(tester);
    await tester.scrollUntilVisible(find.text('Delete all data'), 300);
    await tester.tap(find.text('Delete all data'));
    await tester.pump();
    await h.settle(4200);
    expect(find.text('Delete all data'), findsOneWidget);
    await h.dispose();
  });
}
