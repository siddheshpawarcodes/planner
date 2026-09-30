import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planner_app/app/dev/scenarios.dart';
import 'package:planner_app/app/state/actions.dart';
import 'package:planner_app/app/state/ui_state.dart';
import 'package:planner_app/data/backup/sync.dart';
import 'package:planner_app/data/settings.dart';
import 'package:planner_app/features/settings/settings_page.dart';

import 'harness.dart';

Future<Harness> openSettings(WidgetTester tester) async {
  final h = await pumpScenario(tester, Scenario.tue);
  h.container.read(actionsProvider).goTab(AppTab.plan);
  await h.settle(600);
  h.container.read(actionsProvider).goTab(AppTab.settings);
  await h.settle(800);
  return h;
}

/// Slow drags (no fling) until "Delete all data" sits mid-screen.
Future<void> revealDelete(WidgetTester tester, Harness h) async {
  final list = find.descendant(of: find.byType(SettingsPage), matching: find.byType(Scrollable)).first;
  for (var i = 0; i < 40 && find.text('Delete all data').evaluate().isEmpty; i++) {
    await tester.timedDrag(list, const Offset(0, -150), const Duration(milliseconds: 600));
    await h.settle(200);
  }
  while (tester.getCenter(find.text('Delete all data')).dy > 600) {
    await tester.timedDrag(list, const Offset(0, -80), const Duration(milliseconds: 600));
    await h.settle(200);
  }
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
    await revealDelete(tester, h);
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
    await revealDelete(tester, h);
    await tester.tap(find.text('Delete all data'));
    await tester.pump();
    await h.settle(4200);

    expect(find.text('Delete all data'), findsOneWidget);
    await h.dispose();
  });

  testWidgets('Google Drive: connect, back up, restore sheet, conflict chip', (tester) async {
    final h = await openSettings(tester);
    final list = find.descendant(of: find.byType(SettingsPage), matching: find.byType(Scrollable)).first;
    while (find.text('Google Drive').evaluate().isEmpty) {
      await tester.timedDrag(list, const Offset(0, -150), const Duration(milliseconds: 600));
      await h.settle(200);
    }
    expect(find.text('Not connected'), findsOneWidget);
    await tester.tap(find.text('Google Drive'));
    await h.settle(800);
    expect(find.text('Planner only sees the one backup file it creates. It can’t read the rest of your Drive.'), findsOneWidget);
    await tester.tap(find.text('Connect Google Drive'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Waiting for Google…'), findsOneWidget);
    await h.settle(4000);
    expect(find.text('you@gmail.com'), findsOneWidget);
    expect(find.text('Back up now'), findsOneWidget);
    expect(h.data.driveAccount, 'you@gmail.com');

    await tester.tap(find.text('Restore from Drive'));
    await h.settle(700);
    expect(find.text('Replace this phone’s plan with the Drive backup?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await h.settle(700);

    // Offline: backup waits, and says so.
    h.container.read(onlineProvider.notifier).set(false);
    await h.settle(300);
    expect(find.text('Back up when online'), findsOneWidget);
    expect(find.text('Offline, waiting to back up'), findsWidgets);
    h.container.read(onlineProvider.notifier).set(true);
    await h.settle(300);

    // A newer backup from the tablet: the compare cards, and NEEDS A DECISION on Today.
    // Started, not awaited: the stand-in's delays run on the test clock.
    h.container.read(syncProvider.notifier).debugConflict();
    await h.settle(2000);
    expect(find.text('Two versions of your plan'), findsOneWidget);
    expect(find.text('Keep this phone'), findsOneWidget);
    h.container.read(actionsProvider).goTab(AppTab.today);
    await h.settle(800);
    expect(find.text('NEEDS A DECISION'), findsOneWidget);
    await h.dispose();
  });
}
