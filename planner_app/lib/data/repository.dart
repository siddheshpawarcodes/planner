import 'dart:convert';

import 'package:drift/drift.dart';

import '../domain/category.dart';
import '../domain/routine.dart';
import '../domain/task.dart';
import 'database.dart';
import 'planner_data.dart';
import 'settings.dart';

/// Local-first persistence. Every change is written here before the
/// in-memory state updates, and long before any animation explains it.
abstract class PlannerRepository {
  Future<PlannerData> load();
  Future<void> putTasks(Iterable<Task> tasks);
  Future<void> putRoutine(Routine routine);
  Future<void> putSettings(Settings settings);
  Future<void> putSeries(Series s);
  Future<void> deleteSeries(String id);
  Future<void> putDeadline(Deadline d);
  Future<void> deleteDeadline(String id);
  Future<void> putMeta(Map<String, Object?> meta);

  /// Replaces everything (restore from Drive, scenario load).
  Future<void> replaceAll(PlannerData data);
  Future<void> clearAll();
}

Map<String, Object?> metaOf(PlannerData d) => {
      'onboarded': d.onboarded,
      'installedDay': d.installedDay,
      'deviceId': d.deviceId,
      'lastSyncAt': d.lastSyncAt?.toIso8601String(),
      'changedSinceSync': d.changedSinceSync,
      'driveAccount': d.driveAccount,
    };

class DriftPlannerRepository implements PlannerRepository {
  DriftPlannerRepository(this.db);
  final PlannerDatabase db;

  static Task _task(TaskRow r) => Task(
        id: r.id,
        title: r.title,
        cat: categoryFromName(r.cat),
        day: r.day,
        start: r.startMinute,
        end: r.endMinute,
        plannedEnd: r.plannedEnd,
        duration: r.duration,
        done: r.done,
        skipped: r.skipped,
        deleted: r.deleted,
        doneAt: r.doneAt,
        priority: Priority.values.firstWhere((p) => p.name == r.priority,
            orElse: () => Priority.normal),
        deadline: r.deadline,
        recurrence: r.recurrence == null ? null : DayRule.decode(r.recurrence!),
        seriesId: r.seriesId,
        movedCount: r.movedCount,
        source: r.source == 'voice' ? Source.voice : Source.manual,
        createdAt: r.createdAt,
        updatedAt: r.updatedAt,
      );

  static TasksTableCompanion _row(Task t) => TasksTableCompanion.insert(
        id: t.id,
        title: t.title,
        cat: t.cat.name,
        day: Value(t.day),
        startMinute: Value(t.start),
        endMinute: Value(t.end),
        plannedEnd: Value(t.plannedEnd),
        duration: t.duration,
        done: Value(t.done),
        skipped: Value(t.skipped),
        deleted: Value(t.deleted),
        doneAt: Value(t.doneAt),
        priority: Value(t.priority.name),
        deadline: Value(t.deadline),
        recurrence: Value(t.recurrence?.encode()),
        seriesId: Value(t.seriesId),
        movedCount: Value(t.movedCount),
        source: Value(t.source.name),
        createdAt: Value(t.createdAt),
        updatedAt: Value(t.updatedAt),
      );

  Future<Map<String, Object?>?> _kv(String key) async {
    final row = await (db.select(db.kvTable)..where((k) => k.key.equals(key)))
        .getSingleOrNull();
    if (row == null) return null;
    return (jsonDecode(row.value) as Map).cast<String, Object?>();
  }

  Future<void> _putKv(String key, Map<String, Object?> value) => db
      .into(db.kvTable)
      .insertOnConflictUpdate(KvRow(key: key, value: jsonEncode(value)));

  @override
  Future<PlannerData> load() async {
    final tasks = [for (final r in await db.select(db.tasksTable).get()) _task(r)];
    final deadlines = [
      for (final r in await db.select(db.deadlinesTable).get())
        Deadline(
            id: r.id,
            title: r.title,
            cat: categoryFromName(r.cat),
            day: r.day,
            minute: r.minute,
            note: r.note)
    ];
    final series = [
      for (final r in await db.select(db.seriesTable).get())
        Series(
            id: r.id,
            title: r.title,
            cat: categoryFromName(r.cat),
            rule: DayRule.decode(r.rule),
            start: r.startMinute,
            end: r.endMinute,
            from: r.fromDay)
    ];
    final routine = await _kv('routine');
    final settings = await _kv('settings');
    final meta = await _kv('meta') ?? const {};
    return PlannerData(
      routine: routine == null ? const Routine() : Routine.fromJson(routine),
      tasks: tasks,
      deadlines: deadlines,
      series: series,
      settings: settings == null ? const Settings() : Settings.fromJson(settings),
      onboarded: meta['onboarded'] as bool? ?? false,
      installedDay: meta['installedDay'] as int?,
      deviceId: meta['deviceId'] as String? ?? 'this-phone',
      lastSyncAt: meta['lastSyncAt'] is String
          ? DateTime.tryParse(meta['lastSyncAt']! as String)
          : null,
      changedSinceSync: meta['changedSinceSync'] as bool? ?? false,
      driveAccount: meta['driveAccount'] as String?,
    );
  }

  @override
  Future<void> putTasks(Iterable<Task> tasks) => db.batch((b) {
        for (final t in tasks) {
          b.insert(db.tasksTable, _row(t), mode: InsertMode.insertOrReplace);
        }
      });

  @override
  Future<void> putRoutine(Routine routine) => _putKv('routine', routine.toJson());

  @override
  Future<void> putSettings(Settings settings) =>
      _putKv('settings', settings.toJson());

  @override
  Future<void> putMeta(Map<String, Object?> meta) => _putKv('meta', meta);

  @override
  Future<void> putSeries(Series s) => db.into(db.seriesTable).insertOnConflictUpdate(
      SeriesRow(
          id: s.id,
          title: s.title,
          cat: s.cat.name,
          rule: s.rule.encode(),
          startMinute: s.start,
          endMinute: s.end,
          fromDay: s.from));

  @override
  Future<void> deleteSeries(String id) =>
      (db.delete(db.seriesTable)..where((s) => s.id.equals(id))).go();

  @override
  Future<void> putDeadline(Deadline d) => db
      .into(db.deadlinesTable)
      .insertOnConflictUpdate(DeadlineRow(
          id: d.id,
          title: d.title,
          cat: d.cat.name,
          day: d.day,
          minute: d.minute,
          note: d.note));

  @override
  Future<void> deleteDeadline(String id) =>
      (db.delete(db.deadlinesTable)..where((s) => s.id.equals(id))).go();

  @override
  Future<void> replaceAll(PlannerData data) => db.transaction(() async {
        await _clear();
        await putTasks(data.tasks);
        for (final s in data.series) {
          await putSeries(s);
        }
        for (final d in data.deadlines) {
          await putDeadline(d);
        }
        await putRoutine(data.routine);
        await putSettings(data.settings);
        await putMeta(metaOf(data));
      });

  Future<void> _clear() async {
    await db.delete(db.tasksTable).go();
    await db.delete(db.deadlinesTable).go();
    await db.delete(db.seriesTable).go();
    await db.delete(db.kvTable).go();
  }

  @override
  Future<void> clearAll() => db.transaction(_clear);
}

/// Volatile repository for tests and previews. [failNext] simulates a local
/// write failure ("Not saved, tap to retry").
class MemoryPlannerRepository implements PlannerRepository {
  MemoryPlannerRepository([PlannerData? initial]) : _data = initial ?? const PlannerData();
  PlannerData _data;
  bool failNext = false;
  int writes = 0;

  PlannerData get data => _data;

  Future<void> _write(PlannerData Function(PlannerData) f) async {
    writes++;
    if (failNext) {
      failNext = false;
      throw StateError('write failed');
    }
    _data = f(_data);
  }

  @override
  Future<PlannerData> load() async => _data;

  @override
  Future<void> putTasks(Iterable<Task> tasks) => _write((d) {
        final byId = {for (final t in d.tasks) t.id: t};
        for (final t in tasks) {
          byId[t.id] = t;
        }
        return d.copyWith(tasks: byId.values.toList());
      });

  @override
  Future<void> putRoutine(Routine routine) => _write((d) => d.copyWith(routine: routine));

  @override
  Future<void> putSettings(Settings settings) =>
      _write((d) => d.copyWith(settings: settings));

  @override
  Future<void> putSeries(Series s) => _write((d) =>
      d.copyWith(series: [...d.series.where((x) => x.id != s.id), s]));

  @override
  Future<void> deleteSeries(String id) =>
      _write((d) => d.copyWith(series: d.series.where((x) => x.id != id).toList()));

  @override
  Future<void> putDeadline(Deadline dl) => _write((d) =>
      d.copyWith(deadlines: [...d.deadlines.where((x) => x.id != dl.id), dl]));

  @override
  Future<void> deleteDeadline(String id) => _write(
      (d) => d.copyWith(deadlines: d.deadlines.where((x) => x.id != id).toList()));

  @override
  Future<void> putMeta(Map<String, Object?> meta) => _write((d) => d.copyWith(
        onboarded: meta['onboarded'] as bool?,
        installedDay: meta['installedDay'] as int?,
        changedSinceSync: meta['changedSinceSync'] as bool?,
        lastSyncAt: meta['lastSyncAt'] is String ? DateTime.tryParse(meta['lastSyncAt']! as String) : null,
        driveAccount: meta['driveAccount'] as String?,
      ));

  @override
  Future<void> replaceAll(PlannerData data) => _write((_) => data);

  @override
  Future<void> clearAll() => _write((_) => const PlannerData());
}
