import 'routine.dart';
import 'scheduler.dart';
import 'task.dart';

/// How far ahead recurring occurrences are materialised as tasks.
const int kSeriesHorizonDays = 28;

/// Id of the occurrence of [seriesId] on [day].
String occurrenceId(String seriesId, int day) => '$seriesId@$day';

/// Materialises a series into dated tasks between [fromDay] and [toDay]
/// (inclusive), skipping days that already have an occurrence (so a moved,
/// skipped or completed occurrence is never recreated).
///
/// The prototype only listed series under Upcoming › Repeats. A production
/// planner has to show each occurrence on its day, so occurrences are real
/// tasks with a `seriesId`; every scheduling path treats them like any other
/// task. Each lands at the series time when that is free, otherwise at the
/// first free slot after it.
List<Task> materializeSeries(
  Series s,
  List<Task> all,
  Routine r, {
  required int fromDay,
  required int toDay,
  DateTime? createdAt,
}) {
  // An occurrence keeps its id when moved, so dedupe by id and by day.
  final haveIds = {for (final t in all) if (t.seriesId == s.id) t.id};
  final haveDays = {
    for (final t in all)
      if (t.seriesId == s.id && t.day != null && !t.deleted) t.day!
  };
  final out = <Task>[];
  var tasks = all;
  final len = s.end - s.start;
  for (var d = fromDay < s.from ? s.from : fromDay; d <= toDay; d++) {
    if (!s.rule.matches(d) || haveIds.contains(occurrenceId(s.id, d)) || haveDays.contains(d)) {
      continue;
    }
    final sl = findSlot(d, len, r, tasks, at: s.start, after: s.start);
    final start = sl?.start ?? s.start;
    final t = Task.make(occurrenceId(s.id, d), s.title, s.cat, d, start, len,
            recurrence: s.rule, createdAt: createdAt)
        .copyWith(seriesId: s.id);
    out.add(t);
    tasks = [...tasks, t];
  }
  return out;
}

/// Future, undone occurrences to remove when a series stops.
List<Task> endSeries(String seriesId, List<Task> all, {required int fromDay}) => [
      for (final t in all)
        if (t.seriesId == seriesId && !t.done && !t.deleted && (t.day ?? 0) >= fromDay)
          t.copyWith(deleted: true)
    ];
