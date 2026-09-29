import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/settings.dart';
import '../../domain/capacity.dart';
import '../../domain/layout.dart';
import '../../domain/routine.dart';
import '../../domain/task.dart';
import 'clock.dart';
import 'staging.dart';
import 'store.dart';
import 'ui_state.dart';

final routineProvider =
    Provider<Routine>((ref) => ref.watch(plannerStoreProvider.select((d) => d.routine)));

final tasksProvider =
    Provider<List<Task>>((ref) => ref.watch(plannerStoreProvider.select((d) => d.tasks)));

final settingsProvider =
    Provider<Settings>((ref) => ref.watch(plannerStoreProvider.select((d) => d.settings)));

final historyDaysProvider = Provider<int>((ref) {
  final today = ref.watch(todayProvider);
  return ref.watch(plannerStoreProvider.select((d) => d.historyDays(today)));
});

/// Settings › Motion wins; System follows the platform flag.
final reducedMotionProvider = Provider<bool>((ref) {
  final s = ref.watch(settingsProvider).reducedMotion;
  return s ?? ref.watch(platformReducedMotionProvider);
});

/// Script multiplier (prototype `M()`): 1, or 0.05 when reduced.
final motionFactorProvider =
    Provider<double>((ref) => ref.watch(reducedMotionProvider) ? 0.05 : 1);

/// Tasks with visual holds applied (prototype `eff`): a task being
/// rescheduled is drawn at its old spot for a beat after the data moved.
final effectiveTasksProvider = Provider<List<Task>>((ref) {
  final tasks = ref.watch(tasksProvider);
  final hold = ref.watch(stagingProvider.select((s) => s.hold));
  if (hold.isEmpty) return tasks;
  return [
    for (final t in tasks)
      if (hold[t.id] case final h?)
        t.copyWith(day: h.day, start: h.start, end: h.end)
      else
        t
  ];
});

/// Effective tasks that are on screen (not hidden or staged for placement).
/// Capacity and the odometer count these, so they update as each one lands.
final visibleTasksProvider = Provider<List<Task>>((ref) {
  final eff = ref.watch(effectiveTasksProvider);
  final place = ref.watch(stagingProvider.select((s) => s.place));
  if (place.isEmpty) return eff;
  return [
    for (final t in eff)
      if (place[t.id] != PlaceStage.hidden && place[t.id] != PlaceStage.staged) t
  ];
});

/// The laid-out day (`dayLayoutProvider(day)`).
final dayLayoutProvider = Provider.family<DayLayout, int>((ref, day) =>
    buildDay(day, ref.watch(routineProvider), ref.watch(effectiveTasksProvider)));

/// Capacity for [day] (`capacityProvider(day)`): today counts from now.
final capacityProvider = Provider.family<Capacity, int>((ref, day) {
  final today = ref.watch(todayProvider);
  final from = day == today ? ref.watch(nowMinuteProvider) : 0;
  final all = ref.watch(visibleTasksProvider);
  return capOf(day, ref.watch(routineProvider), all, from,
      weekendCap: learnedWeekendCap(day, all,
          historyDays: ref.watch(historyDaysProvider)));
});

/// The day Today is showing (today or tomorrow).
final shownDayProvider = Provider<int>(
    (ref) => ref.watch(todayProvider) + ref.watch(todayUiProvider.select((u) => u.dayOffset)));
