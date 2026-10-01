import 'package:flutter_test/flutter_test.dart';
import 'package:planner_app/app/dev/scenarios.dart';
import 'package:planner_app/app/state/actions.dart';
import 'package:planner_app/app/state/derived.dart';
import 'package:planner_app/app/state/ui_state.dart';
import 'package:planner_app/domain/time.dart';
import 'package:planner_app/features/notifications/notification_service.dart';
import 'package:planner_app/widgets/controls.dart';

import 'harness.dart';

/// README 11, "the final quality test": one install lived from Tuesday's
/// onboarding to Sunday's review, on one store and one clock. Shared by
/// `test/app/acceptance_test.dart` (host) and `integration_test/` (device).
Future<void> acceptanceJourney(WidgetTester tester) async {
  // First launch on Tuesday 19:40 (main.dart stamps the install day).
  final tue = dayOf(protoMonday) + 1;
  final wed = tue + 1, thu = tue + 2, sat = tue + 4, sun = tue + 5;
  final notes = NoNotifications();
  final h = await pumpScenario(tester, Scenario.onboard,
      edit: (d) => d.copyWith(installedDay: tue),
      overrides: [notificationServiceProvider.overrideWithValue(notes)]);
  Future<void> tap(String text, [int ms = 500]) async {
    await tester.tap(find.text(text));
    await h.settle(ms);
  }

  Future<void> jumpTo(int day, int minute) async {
    Harness.fakeNow = dateOf(day).add(Duration(minutes: minute));
    await h.settle(1500);
  }

  // Onboard: wake 07:00, office 08:00-19:00, dinner 19:00-20:00, sleep 00:00.
  expect(find.text('When do you wake up?'), findsOneWidget);
  expect(find.text('07:00'), findsOneWidget);
  await tap('Continue');
  expect(find.text('08:00'), findsOneWidget);
  await tap('Continue');
  expect(find.text('19:00'), findsOneWidget);
  await tap('Continue');
  expect(find.text('00:00'), findsOneWidget);
  await tap('Continue');
  expect(find.text('Every day, 19:00 → 20:00'), findsOneWidget);
  await tap('Build my rhythm', 2800);
  expect(find.text('3h 10m of realistic time every weekday evening. Up to 6h on weekends.'),
      findsOneWidget);
  final r = h.data.routine;
  expect((r.wake, r.workStart, r.workEnd, r.sleep), (420, 480, 1140, 1440));
  expect(r.commitments.where((c) => c.on).map((c) => (c.title, c.start, c.end)),
      [('Dinner', 1140, 1200)]);
  await tap('Open Today', 1800);
  expect(notes.asked, 1, reason: 'notifications are asked for once, after onboarding');

  // Tue 19:40: the empty evening, then the three-task request.
  expect(find.text('No plans yet.'), findsOneWidget);
  expect(find.text('20:00 → 23:30 open'), findsOneWidget);
  await tester.tap(find.bySemanticsLabel('Talk to Planner'));
  await h.settle(14500); // listen, understand, confirm, success, placement
  final byTitle = {for (final t in h.data.tasks) t.title: t};
  expect([
    for (final n in ['Study polity', 'Exercise', 'Learn Flutter'])
      (byTitle[n]!.day, byTitle[n]!.start)
  ], [(wed, 1200), (wed, 1335), (wed, 1380)]);
  final wedCap = h.container.read(capacityProvider(wed));
  expect(wedCap.layout.breaks.map((b) => (b.start, b.end)), [(1320, 1335)]);
  expect((dur(wedCap.planned), dur(wedCap.realistic), dur(wedCap.over)),
      ('3h 45m', '2h 55m', '50m'));
  expect(h.container.read(todayUiProvider).dayOffset, 1, reason: 'Today shows Wednesday');
  expect(find.text('This is 50m more than fits before your wind-down.'), findsOneWidget);

  // Move Flutter: Thursday 20:00, and Wednesday fits again.
  await tap('Move Flutter', 600);
  final fl = h.data.tasks.firstWhere((t) => t.title == 'Learn Flutter');
  expect((fl.day, fl.start, fl.movedCount), (thu, 1200, 1));
  expect(find.text('Learn Flutter moved to Thu 1 Oct, 20:00. Your evening fits again.'),
      findsOneWidget);
  expect(h.container.read(capacityProvider(wed)).over, lessThanOrEqualTo(0));
  expect(find.text('This is 50m more than fits before your wind-down.'), findsNothing);

  // Wed 21:40: Study polity finishes early.
  await jumpTo(wed, 1300);
  await tester.tap(find.descendant(of: find.byType(SegmentedPill<int>), matching: find.text('Today')));
  await h.settle(800);
  expect(find.text('Wednesday 30 September'), findsOneWidget);
  await tester.tap(find.bySemanticsLabel('Complete Study polity'));
  await h.settle(400);
  final pol = h.data.tasks.firstWhere((t) => t.title == 'Study polity');
  expect((pol.done, pol.end, pol.plannedEnd), (true, 1300, 1320));
  expect(find.text('Study polity done early. 20 min back in your evening.'), findsOneWidget);
  expect(find.bySemanticsLabel('1 of 2 done'), findsOneWidget);
  await h.settle(5500); // let the note go

  // Wed 23:05: Exercise is missed; Decide › This weekend.
  await jumpTo(wed, 1385);
  expect(find.text('Exercise didn’t happen.'), findsOneWidget);
  await tap('Decide', 700);
  expect(find.text('Sat 09:00'), findsOneWidget);
  await tap('This weekend', 1800);
  final ex = h.data.tasks.firstWhere((t) => t.title == 'Exercise');
  expect((ex.day, ex.start, ex.end, ex.movedCount), (sat, 540, 585, 1));
  expect(find.text('Exercise moved to Sat 3 Oct, 09:00.'), findsOneWidget);

  // Sunday 21:00: the review tells the week as it happened.
  await jumpTo(sun, 1260);
  h.container.read(actionsProvider).goTab(AppTab.progress);
  await h.settle(1000);
  await tester.scrollUntilVisible(find.text('Review this week'), 200);
  expect(find.text('Review this week'), findsOneWidget);
  h.container.read(actionsProvider).openReview(); // the button's own handler
  await h.settle(1500);
  expect(find.text('Your week, as it happened.'), findsOneWidget);
  Future<void> next() async {
    await tester.tap(find.bySemanticsLabel('Next'));
    await h.settle(1200);
  }

  expect(find.text('Six days with Planner. Each band is a category. Thicker means more of your '
      'time went there.'), findsOneWidget);
  await next();
  expect(find.text('You planned 3 tasks.'), findsOneWidget);
  expect(find.text('You finished 1.'), findsOneWidget);
  expect(find.textContaining('33% completion'), findsOneWidget);
  await next();
  expect(find.text('1h 40m'), findsWidgets);
  expect(find.text('of focused time.'), findsOneWidget);
  await next();
  expect(find.text('Learn Flutter and Exercise found new times'), findsOneWidget);
  expect(find.text('Learn Flutter and Exercise move into next week'), findsOneWidget);
  await next();
  expect(find.text('Your best hours were 20:00 → 22:00.'), findsOneWidget);
  expect(find.text('Wednesday'), findsOneWidget);
  await next();
  expect(find.text('Two tasks carry into next week. No deadlines are on the way.'), findsOneWidget);
  await tap('Plan next week', 1200);
  expect(h.container.read(currentTabProvider), AppTab.plan);
  await h.dispose();
}
