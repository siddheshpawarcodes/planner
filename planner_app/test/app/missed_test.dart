import 'package:flutter_test/flutter_test.dart';
import 'package:planner_app/app/dev/scenarios.dart';
import 'package:planner_app/app/state/staging.dart';

import 'harness.dart';

void main() {
  testWidgets('23:05: Decide → This weekend moves Exercise to Sat 09:00', (tester) async {
    final h = await pumpScenario(tester, Scenario.missed);
    await tester.tap(find.text('Decide'));
    await h.settle(700);
    expect(find.text('What should we do with this?'), findsOneWidget);
    expect(find.text('Exercise was planned for Wed 22:15 → 23:00.'), findsOneWidget);
    expect(find.text('No room left today'), findsOneWidget);
    expect(find.text('Tomorrow 21:00'), findsOneWidget);
    expect(find.text('Sat 09:00'), findsOneWidget);
    expect(find.text('Counts as a decision'), findsOneWidget);

    await tester.tap(find.text('This weekend'));
    await tester.pump();
    final ex = h.data.task('t2')!;
    final sat = h.data.installedDay! + 4;
    expect((ex.day, ex.start, ex.end), (sat, 540, 585), reason: 'committed first');
    expect(ex.movedCount, 1, reason: 'Rescheduled +1');
    expect(h.container.read(stagingProvider).hold.containsKey('t2'), isTrue,
        reason: 'held at its old spot while the sheet closes');

    await h.settle(400);
    final st = h.container.read(stagingProvider);
    expect(st.hold.containsKey('t2'), isFalse);
    expect(st.leaving.containsKey('t2'), isTrue, reason: 'flying out');
    expect(find.text('Exercise moved to Sat 3 Oct, 09:00.'), findsOneWidget);
    await h.settle(1400);
    expect(h.container.read(stagingProvider).leaving, isEmpty);
    expect(find.text('Exercise didn’t happen.'), findsNothing);
    await h.dispose();
  });

  testWidgets('Choose a day lists seven days with times or Full', (tester) async {
    final h = await pumpScenario(tester, Scenario.missed);
    await tester.tap(find.text('Decide'));
    await h.settle(700);
    await tester.tap(find.text('Choose a day'));
    await h.settle(600);
    expect(find.text('Full'), findsOneWidget); // tonight
    expect(find.text('10:00'), findsWidgets); // the weekend default
    await h.dispose();
  });

  testWidgets('Detail › Reschedule asks when it should happen', (tester) async {
    final h = await pumpScenario(tester, Scenario.wed);
    await tester.tap(find.text('Exercise').first);
    await h.settle(700);
    await tester.tap(find.text('Reschedule'));
    await h.settle(700);
    expect(find.text('When should this happen?'), findsOneWidget);
    await h.dispose();
  });
}
