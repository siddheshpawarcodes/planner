import '../domain/routine.dart';
import '../domain/task.dart';
import 'settings.dart';

/// Everything Planner stores, as one immutable snapshot. The store holds the
/// current one in memory; the repository persists every change first.
class PlannerData {
  const PlannerData({
    this.routine = const Routine(),
    this.tasks = const [],
    this.deadlines = const [],
    this.series = const [],
    this.settings = const Settings(),
    this.onboarded = false,
    this.installedDay,
    this.deviceId = 'this-phone',
    this.lastSyncAt,
    this.changedSinceSync = false,
  });

  final Routine routine;

  /// All tasks, including soft-deleted ones (kept so Undo works).
  final List<Task> tasks;
  final List<Deadline> deadlines;
  final List<Series> series;
  final Settings settings;
  final bool onboarded;

  /// Epoch day of the first launch; drives "days with Planner" and the
  /// 14-day history rule.
  final int? installedDay;
  final String deviceId;
  final DateTime? lastSyncAt;

  /// Local edits since the last Drive sync (conflict detection).
  final bool changedSinceSync;

  int historyDays(int today) =>
      installedDay == null ? 0 : (today - installedDay!).clamp(0, 100000);

  Task? task(String id) {
    for (final t in tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  PlannerData copyWith({
    Routine? routine,
    List<Task>? tasks,
    List<Deadline>? deadlines,
    List<Series>? series,
    Settings? settings,
    bool? onboarded,
    int? installedDay,
    String? deviceId,
    DateTime? lastSyncAt,
    bool? changedSinceSync,
  }) =>
      PlannerData(
        routine: routine ?? this.routine,
        tasks: tasks ?? this.tasks,
        deadlines: deadlines ?? this.deadlines,
        series: series ?? this.series,
        settings: settings ?? this.settings,
        onboarded: onboarded ?? this.onboarded,
        installedDay: installedDay ?? this.installedDay,
        deviceId: deviceId ?? this.deviceId,
        lastSyncAt: lastSyncAt ?? this.lastSyncAt,
        changedSinceSync: changedSinceSync ?? this.changedSinceSync,
      );
}
