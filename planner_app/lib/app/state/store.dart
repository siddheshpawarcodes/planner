import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/planner_data.dart';
import '../../data/repository.dart';
import '../../data/settings.dart';
import '../../domain/routine.dart';
import '../../domain/task.dart';

/// Overridden in `main` (and in tests) with the opened repository.
final repositoryProvider = Provider<PlannerRepository>(
    (ref) => throw UnimplementedError('repositoryProvider must be overridden'));

/// Overridden in `main` with the data loaded before `runApp`, so the store is
/// synchronous from the first frame.
final initialDataProvider = Provider<PlannerData>((ref) => const PlannerData());

final plannerStoreProvider =
    NotifierProvider<PlannerStore, PlannerData>(PlannerStore.new);

/// The single source of truth. Every mutation is written to the repository
/// first; only when that succeeds does the in-memory state change. UI staging
/// (placement, hold, leaving, sweeping) lives elsewhere and never gates this.
class PlannerStore extends Notifier<PlannerData> {
  var _seq = 0;

  /// Raised when a local write fails ("Not saved, tap to retry").
  final writeErrors = ValueNotifier<Object?>(null);

  PlannerRepository get _repo => ref.read(repositoryProvider);

  @override
  PlannerData build() => ref.watch(initialDataProvider);

  /// A fresh task id, unique across restarts.
  String newId() =>
      't${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${(_seq++).toRadixString(36)}';

  Future<bool> _guard(Future<void> Function() write) async {
    try {
      await write();
      writeErrors.value = null;
      return true;
    } catch (e) {
      writeErrors.value = e;
      return false;
    }
  }

  PlannerData _touched(PlannerData d) =>
      d.changedSinceSync ? d : d.copyWith(changedSinceSync: true);

  /// Upserts [changed] tasks. Returns false (and leaves state alone) when the
  /// write fails.
  Future<bool> putTasks(Iterable<Task> changed) async {
    final list = [
      for (final t in changed) t.copyWith(updatedAt: DateTime.now())
    ];
    if (list.isEmpty) return true;
    final ok = await _guard(() => _repo.putTasks(list));
    if (!ok) return false;
    final byId = {for (final t in list) t.id: t};
    final next = <Task>[];
    for (final t in state.tasks) {
      next.add(byId.remove(t.id) ?? t);
    }
    next.addAll(byId.values); // new tasks
    state = _touched(state.copyWith(tasks: next));
    await _markDirty();
    return true;
  }

  /// Writes every task in [next] that is not identical to the current one
  /// (domain functions return unchanged instances as-is).
  Future<bool> commitTaskList(List<Task> next) {
    final cur = {for (final t in state.tasks) t.id: t};
    return putTasks(next.where((t) => !identical(cur[t.id], t)));
  }

  Future<bool> updateTask(String id, Task Function(Task t) f) {
    final t = state.task(id);
    if (t == null) return Future.value(false);
    return putTasks([f(t)]);
  }

  Future<bool> setRoutine(Routine r) async {
    final ok = await _guard(() => _repo.putRoutine(r));
    if (ok) {
      state = _touched(state.copyWith(routine: r));
      await _markDirty();
    }
    return ok;
  }

  Future<bool> setSettings(Settings s) async {
    final ok = await _guard(() => _repo.putSettings(s));
    if (ok) state = state.copyWith(settings: s);
    return ok;
  }

  Future<bool> putSeries(Series s) async {
    final ok = await _guard(() => _repo.putSeries(s));
    if (ok) {
      state = _touched(state.copyWith(
          series: [...state.series.where((x) => x.id != s.id), s]));
      await _markDirty();
    }
    return ok;
  }

  Future<bool> deleteSeries(String id) async {
    final ok = await _guard(() => _repo.deleteSeries(id));
    if (ok) {
      state = _touched(
          state.copyWith(series: state.series.where((x) => x.id != id).toList()));
    }
    return ok;
  }

  Future<bool> putDeadline(Deadline d) async {
    final ok = await _guard(() => _repo.putDeadline(d));
    if (ok) {
      state = _touched(state.copyWith(
          deadlines: [...state.deadlines.where((x) => x.id != d.id), d]));
      await _markDirty();
    }
    return ok;
  }

  Future<bool> setMeta({
    bool? onboarded,
    int? installedDay,
    DateTime? lastSyncAt,
    bool? changedSinceSync,
  }) async {
    final next = state.copyWith(
        onboarded: onboarded,
        installedDay: installedDay,
        lastSyncAt: lastSyncAt,
        changedSinceSync: changedSinceSync);
    final ok = await _guard(() => _repo.putMeta(metaOf(next)));
    if (ok) state = next;
    return ok;
  }

  Future<void> _markDirty() async {
    if (!state.changedSinceSync) return;
    unawaited(_guard(() => _repo.putMeta(metaOf(state))));
  }

  /// Replaces everything (restore, scenarios, delete all data).
  Future<bool> replaceAll(PlannerData data) async {
    final ok = await _guard(() => _repo.replaceAll(data));
    if (ok) state = data;
    return ok;
  }
}
