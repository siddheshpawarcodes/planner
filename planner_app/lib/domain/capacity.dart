import 'base_day.dart';
import 'category.dart';
import 'layout.dart';
import 'routine.dart';
import 'task.dart';
import 'time.dart';

/// One planned segment of the capacity bar, in time order.
class CapacitySegment {
  const CapacitySegment(this.cat, this.minutes, this.taskId);
  final Category cat;
  final int minutes;
  final String taskId;
}

class Capacity {
  const Capacity({
    required this.available,
    required this.protectedMinutes,
    required this.breaks,
    required this.buffer,
    required this.realistic,
    required this.planned,
    required this.done,
    required this.segments,
    required this.layout,
  });

  /// Non-fixed time from `from` to sleep.
  final int available;
  final int protectedMinutes;
  final int breaks;
  final int buffer;
  final int realistic;

  /// Undone task minutes still ahead.
  final int planned;

  /// Minutes of finished tasks (whole day).
  final int done;
  final List<CapacitySegment> segments;
  final DayLayout layout;

  /// `planned − realistic`; the calm row appears when this exceeds 15.
  int get over => planned - realistic;
  bool get isOver => over > 15;
}

/// The weekend cap before Planner knows the user's pace.
const int kWeekendDefaultCap = 360;

/// Days of history needed before the weekend cap is learned.
const int kHistoryDaysForLearning = 14;

/// Capacity for [day] counting from minute [from] (prototype `capOf`).
///
/// Today counts from now; other days from 0. On weekends realistic time is
/// capped at [weekendCap] (6h by default; the learned 75th percentile of
/// finished minutes once 14 days of history exist, see [learnedWeekendCap]).
Capacity capOf(int day, Routine r, List<Task> all, num from,
    {int? weekendCap}) {
  final b = buildDay(day, r, all);
  final f = from.floor();
  int cl(int s, int e) {
    final v = e - (s > f ? s : f);
    return v > 0 ? v : 0;
  }

  var avail = 0, brk = 0, planned = 0, done = 0;
  final segs = <CapacitySegment>[];
  for (final x in b.seq) {
    if (x.kind == ItemKind.open ||
        x.kind == ItemKind.task ||
        x.kind == ItemKind.breakTime ||
        x.kind == ItemKind.protected) {
      avail += cl(x.start, x.end);
    }
    if (x.kind == ItemKind.breakTime) brk += cl(x.start, x.end);
  }
  var prot = 0;
  for (final x in b.base) {
    if (x.kind == ItemKind.protected) prot += cl(x.start, x.end);
  }
  for (final t in b.tasks) {
    if (t.done) {
      done += t.end! - t.start!;
      continue;
    }
    final m = cl(t.start!, t.end!);
    if (m > 0) {
      planned += m;
      segs.add(CapacitySegment(t.cat, m, t.id));
    }
  }
  final rest = avail - prot - brk;
  final buffer = rest < 0 ? 0 : (rest > 20 ? 20 : rest);
  var real = avail - prot - brk - buffer;
  if (real < 0) real = 0;
  if (isWeekend(day)) {
    final cap = weekendCap ?? kWeekendDefaultCap;
    if (real > cap) real = cap;
  }
  return Capacity(
    available: avail,
    protectedMinutes: prot,
    breaks: brk,
    buffer: buffer,
    realistic: real,
    planned: planned,
    done: done,
    segments: segs,
    layout: b,
  );
}

/// The learned weekend cap: the 75th percentile of finished minutes on past
/// days with the same weekday, once [kHistoryDaysForLearning] days of history
/// exist. Returns null (use the 6h default) before that.
int? learnedWeekendCap(int day, List<Task> all, {required int historyDays}) {
  if (historyDays < kHistoryDaysForLearning) return null;
  final wd = weekday0(day);
  final perDay = <int, int>{};
  for (final t in all) {
    if (!t.done || t.deleted || t.day == null || t.day! >= day) continue;
    if (weekday0(t.day!) != wd) continue;
    perDay[t.day!] = (perDay[t.day!] ?? 0) + (t.end! - t.start!);
  }
  if (perDay.isEmpty) return null;
  final v = perDay.values.toList()..sort();
  final idx = ((v.length - 1) * 0.75).round();
  return v[idx];
}

/// Copy for the over-capacity calm row (README 2.9): honest for the first
/// 14 days, history-based after that.
String overCapacityText(int day, int over, {required int historyDays}) {
  if (isWeekend(day)) {
    return 'This is ${dur(over)} more than a comfortable weekend day.';
  }
  if (historyDays >= kHistoryDaysForLearning) {
    return 'This is ${dur(over)} more than you usually finish in an evening.';
  }
  return 'This is ${dur(over)} more than fits before your wind-down.';
}
