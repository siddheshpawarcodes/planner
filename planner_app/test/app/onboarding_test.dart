import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planner_app/app/dev/scenarios.dart';
import 'package:planner_app/app/state/actions.dart';
import 'package:planner_app/app/state/ui_state.dart';
import 'package:planner_app/features/onboarding/onboarding_widgets.dart';

import 'harness.dart';

Future<void> _continue(WidgetTester tester, Harness h, [String label = 'Continue']) async {
  await tester.tap(find.text(label));
  await h.settle(500);
}

void main() {
  testWidgets('first launch: five questions, the assembly, then Today (acceptance)', (tester) async {
    final h = await pumpScenario(tester, Scenario.onboard);
    expect(h.data.onboarded, isFalse);
    expect(find.text('When do you wake up?'), findsOneWidget);
    expect(find.text('Your day starts here. Planner never schedules before it.'), findsOneWidget);
    expect(find.text('07:00'), findsOneWidget);
    expect(find.bySemanticsLabel('When do you wake up? 07:00'), findsOneWidget);
    expect(find.bySemanticsLabel('Back'), findsNothing);

    await tester.tap(find.bySemanticsLabel('15 minutes later'));
    await tester.pump();
    expect(find.text('07:15'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('15 minutes earlier'));
    await tester.pump();
    expect(find.text('07:00'), findsOneWidget);

    await _continue(tester, h);
    expect(find.text('When does work begin?'), findsOneWidget);
    expect(find.text('08:00'), findsOneWidget);
    expect(find.text('I don’t work fixed hours'), findsOneWidget);
    expect(find.text('Office 08:00 → 19:00'), findsOneWidget);
    await _continue(tester, h);
    expect(find.text('When does work end?'), findsOneWidget);
    expect(find.text('19:00'), findsOneWidget);
    await _continue(tester, h);
    expect(find.text('When do you normally sleep?'), findsOneWidget);
    expect(find.text('00:00'), findsOneWidget);
    await _continue(tester, h);
    expect(find.text('What recurring commitments do you have?'), findsOneWidget);
    expect(find.text('Every day, 19:00 → 20:00'), findsOneWidget);
    expect(find.text('Saturdays, 09:00 → 10:00'), findsOneWidget);
    expect(find.text('Sundays, 18:00 → 18:30'), findsOneWidget);

    await tester.tap(find.text('Build my rhythm'));
    await tester.pump();
    // The routine commits before the assembly explains it.
    expect(h.data.onboarded, isTrue);
    expect(h.repo.data.onboarded, isTrue);
    final r = h.data.routine;
    expect((r.wake, r.workStart, r.workEnd, r.sleep, r.noFixedWork), (420, 480, 1140, 1440, false));
    expect(find.text('Building your rhythm'), findsOneWidget);

    await h.settle(2800);
    expect(find.text('Your rhythm is ready.'), findsOneWidget);
    expect(find.text('3h 10m of realistic time every weekday evening. Up to 6h on weekends.'), findsOneWidget);
    expect(find.text('Office'), findsOneWidget);
    expect(find.text('Getting ready'), findsOneWidget);
    expect(find.text('Wind-down'), findsOneWidget);
    expect(find.text('Your time'), findsOneWidget);

    await tester.tap(find.text('Open Today'));
    await h.settle(1200);
    expect(find.text('No plans yet.'), findsOneWidget);
    expect(find.text('20:00 → 23:30 open'), findsOneWidget);
    expect(h.container.read(currentTabProvider), AppTab.today);
    await h.dispose();
  });

  testWidgets('the ruler drags 2 px per minute; no fixed hours skips work end', (tester) async {
    final h = await pumpScenario(tester, Scenario.onboard);
    await tester.drag(find.byType(ObRuler), const Offset(-60, 0));
    await tester.pump();
    expect(find.text('07:30'), findsOneWidget);
    await tester.drag(find.byType(ObRuler), const Offset(30, 0));
    await tester.pump();
    expect(find.text('07:15'), findsOneWidget);

    await _continue(tester, h);
    await tester.tap(find.text('I don’t work fixed hours'));
    await tester.pump();
    expect(find.text('Your own time: everything outside sleep and meals'), findsOneWidget);
    await _continue(tester, h);
    expect(find.text('When do you normally sleep?'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Back'));
    await h.settle(500);
    expect(find.text('When does work begin?'), findsOneWidget);
    await h.dispose();
  });

  testWidgets('Add your own adds a switched-on commitment', (tester) async {
    final h = await pumpScenario(tester, Scenario.onboard);
    for (var i = 0; i < 4; i++) {
      await _continue(tester, h);
    }
    await tester.tap(find.text('Add your own'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Evening walk');
    await tester.tap(find.text('21:00'));
    await tester.tap(find.text('1h'));
    await tester.tap(find.text('Weekdays'));
    await tester.pump();
    await tester.tap(find.text('Add'));
    await h.settle(300);
    expect(find.text('Evening walk'), findsOneWidget);
    expect(find.text('Weekdays, 21:00 → 22:00'), findsOneWidget);

    await tester.tap(find.text('Build my rhythm'));
    await tester.pump();
    final walk = h.data.routine.commitments.last;
    expect((walk.title, walk.start, walk.end, walk.on), ('Evening walk', 1260, 1320, true));
    await h.dispose();
  });

  testWidgets('Settings › Edit routine re-runs onboarding prefilled', (tester) async {
    final h = await pumpScenario(tester, Scenario.tue);
    final act = h.container.read(actionsProvider);
    act.goTab(AppTab.settings);
    await h.settle(800);
    expect(find.text('08:00 → 19:00'), findsOneWidget);
    expect(find.text('1 recurring'), findsOneWidget);

    await tester.tap(find.text('Edit routine'));
    await h.settle(800);
    expect(find.text('When do you wake up?'), findsOneWidget);
    // Close keeps the routine as it was.
    await tester.tap(find.bySemanticsLabel('Close, keep the current routine'));
    await h.settle(800);
    expect(find.text('When do you wake up?'), findsNothing);

    await tester.tap(find.text('Edit routine'));
    await h.settle(800);
    for (var i = 0; i < 4; i++) {
      await _continue(tester, h);
    }
    await tester.tap(find.text('Gym'));
    await tester.pump();
    await tester.tap(find.text('Build my rhythm'));
    await h.settle(2800);
    expect(h.data.routine.commitments.where((c) => c.on).map((c) => c.title), ['Dinner', 'Gym']);
    await tester.tap(find.text('Open Today'));
    await h.settle(1000);
    expect(h.container.read(currentTabProvider), AppTab.today);
    expect(find.text('Routine updated. Planner rebuilt your week around it.'), findsOneWidget);
    await h.dispose();
  });
}
