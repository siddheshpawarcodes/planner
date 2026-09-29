import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/dev/scenarios.dart';
import 'app/state/clock.dart';
import 'app/state/store.dart';
import 'data/database.dart';
import 'data/repository.dart';
import 'domain/time.dart';

/// Debug: `--dart-define=PLANNER_SCENARIO=wed` starts at a journey step.
const _scenario = String.fromEnvironment('PLANNER_SCENARIO');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repo = DriftPlannerRepository(PlannerDatabase());
  var data = await repo.load();
  DateTime? pinned;

  if (kDebugMode && _scenario.isNotEmpty) {
    final k = Scenario.values.where((s) => s.name == _scenario).firstOrNull;
    if (k != null) {
      final s = buildScenario(k);
      data = s.data.copyWith(settings: data.settings);
      await repo.replaceAll(data);
      pinned = s.clock;
    }
  }
  if (data.installedDay == null) {
    // First launch. Onboarding (milestone 8) will set the routine; until
    // then the default routine is used.
    data = data.copyWith(installedDay: dayOf(DateTime.now()), onboarded: true);
    await repo.putMeta(metaOf(data));
  }

  final container = ProviderContainer(overrides: [
    repositoryProvider.overrideWithValue(repo),
    initialDataProvider.overrideWithValue(data),
  ]);
  if (pinned != null) container.read(clockProvider.notifier).pin(pinned);
  runApp(UncontrolledProviderScope(container: container, child: const PlannerApp()));
}
