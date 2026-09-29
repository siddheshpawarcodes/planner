import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planner_app/app/app.dart';
import 'package:planner_app/app/dev/scenarios.dart';
import 'package:planner_app/app/state/clock.dart';
import 'package:planner_app/app/state/store.dart';
import 'package:planner_app/data/planner_data.dart';
import 'package:planner_app/data/repository.dart';

/// The prototype's week: Monday 28 September 2026.
final protoMonday = DateTime(2026, 9, 28);

class Harness {
  Harness(this.tester, this.repo, this.container);
  final WidgetTester tester;
  final MemoryPlannerRepository repo;
  final ProviderContainer container;
  static DateTime fakeNow = DateTime(2026, 9, 29, 19, 40);

  PlannerData get data => container.read(plannerStoreProvider);

  Future<void> advance(Duration d) async {
    fakeNow = fakeNow.add(d);
    await tester.pump(const Duration(seconds: 1));
  }

  /// Lets timers and implicit animations run without waiting for the orb
  /// (which animates forever).
  Future<void> settle([int ms = 2500]) async {
    for (var i = 0; i < ms ~/ 100; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> dispose() async {
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.pump(const Duration(seconds: 7));
  }
}

/// Pumps the whole app at a journey step on a 400 × 860 phone.
Future<Harness> pumpScenario(WidgetTester tester, Scenario k,
    {PlannerData Function(PlannerData d)? edit, DateTime? clock}) async {
  final s = buildScenario(k, now: protoMonday);
  final data = edit == null ? s.data : edit(s.data);
  Harness.fakeNow = clock ?? s.clock;
  ClockController.realNow = () => Harness.fakeNow;
  tester.view.physicalSize = const Size(400, 860);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = MemoryPlannerRepository(data);
  final container = ProviderContainer(overrides: [
    repositoryProvider.overrideWithValue(repo),
    initialDataProvider.overrideWithValue(data),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const PlannerApp()));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 600));
  return Harness(tester, repo, container);
}
