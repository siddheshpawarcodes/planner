import 'package:flutter_test/flutter_test.dart';
import 'package:planner_app/app/dev/scenarios.dart';
import 'package:planner_app/domain/category.dart';
import 'package:planner_app/domain/task.dart';

import 'harness.dart';

void main() {
  testWidgets('Tue 19:40: the empty evening state and 3h 10m realistic', (tester) async {
    final h = await pumpScenario(tester, Scenario.tue);
    expect(find.text('Tuesday 29 September'), findsOneWidget);
    expect(find.text('No plans yet.'), findsOneWidget);
    expect(find.text('Tap the orb, or say “Hey Planner”.'), findsOneWidget);
    expect(find.text('20:00 → 23:30 open'), findsOneWidget);
    expect(find.textContaining('3h 10m', findRichText: true), findsWidgets);
    expect(find.text('19:40'), findsWidgets); // the now pill
    await h.dispose();
  });

  testWidgets('Wed 21:40: completing Study polity early gives 20 min back', (tester) async {
    final h = await pumpScenario(tester, Scenario.wed);
    expect(find.textContaining('Study polity', findRichText: true), findsWidgets);
    await tester.tap(find.bySemanticsLabel('Complete Study polity'));
    await tester.pump();
    final pol = h.data.task('t1')!;
    expect(pol.done, isTrue, reason: 'state commits before any animation');
    expect(pol.end, 1300);
    expect(pol.plannedEnd, 1320);
    expect(h.repo.data.task('t1')!.done, isTrue, reason: 'written to the repository');
    await h.settle(400);
    expect(find.text('Study polity done early. 20 min back in your evening.'), findsOneWidget);
    expect(find.bySemanticsLabel('1 of 2 done'), findsOneWidget);
    // Undo restores the plan.
    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(h.data.task('t1')!.done, isFalse);
    expect(h.data.task('t1')!.end, 1320);
    await h.dispose();
  });

  testWidgets('Wed 23:05: Exercise is missed and the calm prompt shows', (tester) async {
    final h = await pumpScenario(tester, Scenario.missed);
    expect(find.text('Exercise didn’t happen.'), findsOneWidget);
    expect(find.text('What should we do with it?'), findsOneWidget);
    expect(find.text('MISSED'), findsOneWidget);
    await tester.tap(find.text('Later'));
    await h.settle(600);
    expect(find.text('Exercise didn’t happen.'), findsNothing);
    await h.dispose();
  });

  testWidgets('Tomorrow after the voice request: 50m over, Move Flutter', (tester) async {
    final h = await pumpScenario(tester, Scenario.tue, edit: (d) {
      final wed = d.installedDay! + 1;
      return d.copyWith(tasks: [
        ...d.tasks,
        Task.make('a', 'Study polity', Category.study, wed, 1200, 120, source: Source.voice),
        Task.make('b', 'Exercise', Category.body, wed, 1335, 45, source: Source.voice),
        Task.make('c', 'Learn Flutter', Category.build, wed, 1380, 60, source: Source.voice),
      ]);
    });
    await tester.tap(find.text('Tomorrow'));
    await h.settle(800);
    expect(find.text('Wednesday 30 September'), findsOneWidget);
    expect(find.text('This is 50m more than fits before your wind-down.'), findsOneWidget);
    expect(find.text('3 tasks planned', findRichText: true), findsNothing);
    await tester.tap(find.text('Move Flutter'));
    await tester.pump();
    final fl = h.data.task('c')!;
    expect((fl.day, fl.start, fl.movedCount), (h.data.installedDay! + 2, 1200, 1));
    await h.settle(600);
    expect(find.text('Learn Flutter moved to Thu 1 Oct, 20:00. Your evening fits again.'),
        findsOneWidget);
    expect(find.text('This is 50m more than fits before your wind-down.'), findsNothing);
    await h.dispose();
  });

  testWidgets('a failed local write changes nothing and offers a retry', (tester) async {
    final h = await pumpScenario(tester, Scenario.wed);
    h.repo.failNext = true;
    await tester.tap(find.bySemanticsLabel('Complete Study polity'));
    await tester.pump();
    expect(h.data.task('t1')!.done, isFalse);
    await h.settle(300);
    expect(find.text('Not saved, tap to retry'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(h.data.task('t1')!.done, isTrue);
    await h.dispose();
  });

  testWidgets('Strip and Dial switch; the dial shows NOW', (tester) async {
    final h = await pumpScenario(tester, Scenario.wed);
    await tester.tap(find.text('Dial'));
    await h.settle(1200);
    expect(find.text('NOW'), findsWidgets);
    expect(find.text('Mark done'), findsOneWidget);
    await h.dispose();
  });

  testWidgets('reduced motion still commits immediately', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final h = await pumpScenario(tester, Scenario.wed);
    await tester.tap(find.bySemanticsLabel('Complete Study polity'));
    await tester.pump();
    expect(h.data.task('t1')!.done, isTrue);
    await h.dispose();
  });
}
