import 'dart:convert';

import '../domain/routine.dart';
import '../domain/task.dart';
import 'planner_data.dart';
import 'settings.dart';

/// The one JSON document Planner exports and backs up to Drive (README 6.11):
/// `planner-backup.json`, plus `planner-backup-<timestamp>.json` for a kept
/// loser after a conflict or before a restore.
class PlannerSnapshot {
  const PlannerSnapshot({
    required this.exportedAt,
    required this.deviceId,
    required this.routine,
    required this.tasks,
    required this.series,
    required this.deadlines,
    required this.settings,
    this.schemaVersion = currentSchema,
  });

  static const currentSchema = 1;

  final int schemaVersion;
  final DateTime exportedAt;
  final String deviceId;
  final Routine routine;
  final List<Task> tasks;
  final List<Series> series;
  final List<Deadline> deadlines;
  final Settings settings;

  /// Deleted tasks (kept locally only so Undo works) are left out.
  factory PlannerSnapshot.of(PlannerData d, {DateTime? at}) => PlannerSnapshot(
        exportedAt: at ?? DateTime.now(),
        deviceId: d.deviceId,
        routine: d.routine,
        tasks: [for (final t in d.tasks) if (!t.deleted) t],
        series: d.series,
        deadlines: d.deadlines,
        settings: d.settings,
      );

  /// Tasks planned this week, for the conflict compare cards.
  int tasksInWeek(int weekStart) =>
      tasks.where((t) => t.day != null && t.day! >= weekStart && t.day! < weekStart + 7).length;

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'exportedAt': exportedAt.toUtc().toIso8601String(),
        'deviceId': deviceId,
        'routine': routine.toJson(),
        'tasks': [for (final t in tasks) t.toJson()],
        'series': [for (final s in series) s.toJson()],
        'deadlines': [for (final d in deadlines) d.toJson()],
        'settings': settings.toJson(),
      };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  static PlannerSnapshot fromJson(Map<String, Object?> j) {
    List<Map<String, Object?>> list(String k) =>
        [for (final x in (j[k] as List? ?? const [])) (x as Map).cast<String, Object?>()];
    final v = j['schemaVersion'] as int? ?? 0;
    if (v > currentSchema) {
      throw FormatException('Backup schema $v is newer than this version of Planner ($currentSchema).');
    }
    return PlannerSnapshot(
      schemaVersion: v,
      exportedAt: DateTime.parse(j['exportedAt']! as String).toLocal(),
      deviceId: j['deviceId'] as String? ?? 'unknown',
      routine: Routine.fromJson((j['routine']! as Map).cast<String, Object?>()),
      tasks: [for (final t in list('tasks')) Task.fromJson(t)],
      series: [for (final s in list('series')) Series.fromJson(s)],
      deadlines: [for (final d in list('deadlines')) Deadline.fromJson(d)],
      settings: Settings.fromJson((j['settings'] as Map? ?? const {}).cast<String, Object?>()),
    );
  }

  static PlannerSnapshot decode(String s) => fromJson((jsonDecode(s) as Map).cast<String, Object?>());

  /// Applies the snapshot to [base], keeping this install's identity and
  /// history (device id, install day).
  PlannerData applyTo(PlannerData base) => base.copyWith(
        routine: routine,
        tasks: tasks,
        series: series,
        deadlines: deadlines,
        settings: settings,
        onboarded: true,
      );
}
