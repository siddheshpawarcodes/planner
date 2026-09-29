import 'category.dart';
import 'routine.dart';

enum Priority { low, normal, high }

enum Source { voice, manual }

const Object _unset = Object();

class Task {
  const Task({
    required this.id,
    required this.title,
    required this.cat,
    this.day,
    this.start,
    this.end,
    this.plannedEnd,
    required this.duration,
    this.done = false,
    this.skipped = false,
    this.deleted = false,
    this.doneAt,
    this.priority = Priority.normal,
    this.deadline,
    this.recurrence,
    this.seriesId,
    this.movedCount = 0,
    this.source = Source.manual,
    this.createdAt,
    this.updatedAt,
  });

  /// Prototype `mk(id, title, cat, day, s, d, …)`.
  factory Task.make(
    String id,
    String title,
    Category cat,
    int? day,
    int? start,
    int duration, {
    Source source = Source.manual,
    Priority priority = Priority.normal,
    int? deadline,
    DayRule? recurrence,
    int movedCount = 0,
    DateTime? createdAt,
  }) =>
      Task(
        id: id,
        title: title,
        cat: cat,
        day: day,
        start: start,
        end: start == null ? null : start + duration,
        duration: duration,
        source: source,
        priority: priority,
        deadline: deadline,
        recurrence: recurrence,
        movedCount: movedCount,
        createdAt: createdAt,
        updatedAt: createdAt,
      );

  final String id;
  final String title;
  final Category cat;

  /// Epoch day; null means the Unscheduled inbox.
  final int? day;

  /// Minutes from midnight. [end] moves to "now" when finished early.
  final int? start, end;

  /// The original end when finished early.
  final int? plannedEnd;

  /// Requested minutes.
  final int duration;
  final bool done, skipped, deleted;

  /// Minute of the task's day at which it was completed.
  final int? doneAt;
  final Priority priority;

  /// Deadline as an epoch day.
  final int? deadline;
  final DayRule? recurrence;
  final String? seriesId;

  /// Counts toward "Rescheduled".
  final int movedCount;
  final Source source;
  final DateTime? createdAt, updatedAt;

  /// Prototype `live`: placed on a day, not deleted or skipped.
  bool get isLive => !deleted && !skipped && start != null && day != null;
  bool get isScheduled => day != null && start != null;

  /// Scheduled length (end − start); falls back to [duration] when unplaced.
  int get length => (start != null && end != null) ? end! - start! : duration;

  Task copyWith({
    String? title,
    Category? cat,
    Object? day = _unset,
    Object? start = _unset,
    Object? end = _unset,
    Object? plannedEnd = _unset,
    int? duration,
    bool? done,
    bool? skipped,
    bool? deleted,
    Object? doneAt = _unset,
    Priority? priority,
    Object? deadline = _unset,
    Object? recurrence = _unset,
    Object? seriesId = _unset,
    int? movedCount,
    Source? source,
    DateTime? updatedAt,
  }) =>
      Task(
        id: id,
        title: title ?? this.title,
        cat: cat ?? this.cat,
        day: identical(day, _unset) ? this.day : day as int?,
        start: identical(start, _unset) ? this.start : start as int?,
        end: identical(end, _unset) ? this.end : end as int?,
        plannedEnd: identical(plannedEnd, _unset)
            ? this.plannedEnd
            : plannedEnd as int?,
        duration: duration ?? this.duration,
        done: done ?? this.done,
        skipped: skipped ?? this.skipped,
        deleted: deleted ?? this.deleted,
        doneAt: identical(doneAt, _unset) ? this.doneAt : doneAt as int?,
        priority: priority ?? this.priority,
        deadline:
            identical(deadline, _unset) ? this.deadline : deadline as int?,
        recurrence: identical(recurrence, _unset)
            ? this.recurrence
            : recurrence as DayRule?,
        seriesId:
            identical(seriesId, _unset) ? this.seriesId : seriesId as String?,
        movedCount: movedCount ?? this.movedCount,
        source: source ?? this.source,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  /// Places the task at [day] [start] keeping its length.
  Task placed(int day, int start, int end) =>
      copyWith(day: day, start: start, end: end);

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'cat': cat.name,
        'day': day,
        'start': start,
        'end': end,
        'plannedEnd': plannedEnd,
        'duration': duration,
        'done': done,
        'skipped': skipped,
        'deleted': deleted,
        'doneAt': doneAt,
        'priority': priority.name,
        'deadline': deadline,
        'recurrence': recurrence?.encode(),
        'seriesId': seriesId,
        'movedCount': movedCount,
        'source': source.name,
        'createdAt': createdAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
      };

  static Task fromJson(Map<String, Object?> j) => Task(
        id: j['id']! as String,
        title: j['title']! as String,
        cat: categoryFromName(j['cat'] as String?),
        day: j['day'] as int?,
        start: j['start'] as int?,
        end: j['end'] as int?,
        plannedEnd: j['plannedEnd'] as int?,
        duration: j['duration']! as int,
        done: j['done'] as bool? ?? false,
        skipped: j['skipped'] as bool? ?? false,
        deleted: j['deleted'] as bool? ?? false,
        doneAt: j['doneAt'] as int?,
        priority: Priority.values.firstWhere((p) => p.name == j['priority'],
            orElse: () => Priority.normal),
        deadline: j['deadline'] as int?,
        recurrence: j['recurrence'] == null
            ? null
            : DayRule.decode(j['recurrence']! as String),
        seriesId: j['seriesId'] as String?,
        movedCount: j['movedCount'] as int? ?? 0,
        source: j['source'] == 'voice' ? Source.voice : Source.manual,
        createdAt: _date(j['createdAt']),
        updatedAt: _date(j['updatedAt']),
      );

  @override
  String toString() =>
      'Task($id "$title" day=$day $start-$end${done ? ' done' : ''})';
}

DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v) : null;

class Deadline {
  const Deadline({
    required this.id,
    required this.title,
    required this.cat,
    required this.day,
    this.minute,
    this.note,
  });

  final String id, title;
  final Category cat;

  /// Due epoch day and optional minute ("Due 18:00").
  final int day;
  final int? minute;

  /// Optional context, e.g. "3 study blocks planned before it".
  final String? note;

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'cat': cat.name,
        'day': day,
        'minute': minute,
        'note': note,
      };

  static Deadline fromJson(Map<String, Object?> j) => Deadline(
        id: j['id']! as String,
        title: j['title']! as String,
        cat: categoryFromName(j['cat'] as String?),
        day: j['day']! as int,
        minute: j['minute'] as int?,
        note: j['note'] as String?,
      );
}

class Series {
  const Series({
    required this.id,
    required this.title,
    required this.cat,
    required this.rule,
    required this.start,
    required this.end,
    required this.from,
  });

  final String id, title;
  final Category cat;
  final DayRule rule;
  final int start, end;

  /// First epoch day of the series.
  final int from;

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'cat': cat.name,
        'rule': rule.encode(),
        'start': start,
        'end': end,
        'from': from,
      };

  static Series fromJson(Map<String, Object?> j) => Series(
        id: j['id']! as String,
        title: j['title']! as String,
        cat: categoryFromName(j['cat'] as String?),
        rule: DayRule.decode(j['rule']! as String),
        start: j['start']! as int,
        end: j['end']! as int,
        from: j['from']! as int,
      );
}
