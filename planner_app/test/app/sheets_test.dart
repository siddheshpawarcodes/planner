import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planner_app/app/dev/scenarios.dart';
import 'package:planner_app/app/state/staging.dart';
import 'package:planner_app/widgets/controls.dart';

import 'harness.dart';

void main() {
  testWidgets('create: preview, Schedule, then the placement sequence', (tester) async {
    final h = await pumpScenario(tester, Scenario.tue);
    await tester.tap(find.bySemanticsLabel('Add task'));
    await h.settle(600);
    expect(find.text('Planner will find the time'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Read');
    await h.settle(600);
    expect(find.text('Pick a duration'), findsOneWidget);
    expect(find.text('Self'), findsOneWidget, reason: 'category inferred from the title');
    await tester.tap(find.widgetWithText(PlannerChip, '30m'));
    await h.settle(600);
    expect(find.text('Today 20:00 → 20:30'), findsOneWidget);
    expect(find.text('2h 40m of realistic time left after this.'), findsOneWidget);

    await tester.ensureVisible(find.text('Schedule'));
    await tester.pump();
    await tester.tap(find.text('Schedule'));
    await tester.pump();
    final t = h.data.tasks.firstWhere((x) => x.title == 'Read');
    expect((t.day, t.start, t.end), (h.data.installedDay, 1200, 1230),
        reason: 'committed before the sequence runs');
    final staging = h.container.read(stagingProvider);
    expect(staging.place[t.id], PlaceStage.hidden);
    expect(staging.winLit, isTrue);

    await h.settle(1500); // 560 + 850 + scan
    await h.settle(1600);
    final after = h.container.read(stagingProvider);
    expect(after.place.containsKey(t.id), isFalse);
    expect(after.winLit, isFalse);
    expect(find.text('Read placed at today, 20:00.'), findsOneWidget);
    await h.dispose();
  });

  testWidgets('schedule on a later day goes to the week board', (tester) async {
    final h = await pumpScenario(tester, Scenario.tue);
    await tester.tap(find.bySemanticsLabel('Add task'));
    await h.settle(600);
    await tester.enterText(find.byType(TextField), 'Gym');
    await h.settle(600);
    await tester.tap(find.widgetWithText(PlannerChip, '1h'));
    await h.settle(600);
    await tester.tap(find.widgetWithText(PlannerChip, 'Saturday'));
    await tester.pump();
    expect(find.text('Saturday 10:00 → 11:00'), findsOneWidget);
    await tester.ensureVisible(find.text('Schedule'));
    await tester.pump();
    await tester.tap(find.text('Schedule'));
    await h.settle(800);
    expect(find.text('Gym added to Sat 3 Oct, 10:00.'), findsOneWidget);
    await h.dispose();
  });

  testWidgets('detail: rows, skip with Undo, delete needs two taps', (tester) async {
    final h = await pumpScenario(tester, Scenario.wed);
    await tester.tap(find.text('Exercise').first);
    await h.settle(600);
    expect(find.text('Added by'), findsOneWidget);
    expect(find.text('Voice'), findsOneWidget);
    expect(find.text('Planned'), findsOneWidget);
    expect(find.text('New on your plan. History builds as it repeats.'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pump();
    expect(find.text('Tap again to delete'), findsOneWidget);
    expect(h.data.task('t2')!.deleted, isFalse);
    await tester.tap(find.text('Skip'));
    await tester.pump();
    expect(h.data.task('t2')!.skipped, isTrue);
    await h.settle(600);
    expect(find.text('Exercise skipped this time.'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(h.data.task('t2')!.skipped, isFalse);

    await tester.tap(find.text('Exercise').first);
    await h.settle(600);
    await tester.tap(find.text('Delete'));
    await tester.pump();
    await tester.tap(find.text('Tap again to delete'));
    await tester.pump();
    expect(h.data.task('t2')!.deleted, isTrue);
    await h.dispose();
  });

  testWidgets('edit keeps the exact time and says Save', (tester) async {
    final h = await pumpScenario(tester, Scenario.wed);
    await tester.tap(find.text('Exercise').first);
    await h.settle(600);
    await tester.tap(find.text('Edit'));
    await h.settle(600);
    expect(find.text('Edit task'), findsOneWidget);
    expect(find.text('Keeping it at 22:15 if that still fits.'), findsOneWidget);
    await tester.tap(find.widgetWithText(PlannerChip, '30m'));
    await tester.pump();
    await tester.ensureVisible(find.text('Save'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pump();
    final ex = h.data.task('t2')!;
    expect((ex.start, ex.end), (1335, 1365));
    await h.settle(600);
    expect(find.text('Saved.'), findsOneWidget);
    await h.dispose();
  });
}
