import 'base_day.dart';
import 'routine.dart';
import 'task.dart';
import 'time.dart';

/// Proportional layout constants: 1.1 px per minute, 6 px row gap.
const double kPxPerMinute = 1.1;
const double kRowGap = 6;

class DayLayout {
  const DayLayout({
    required this.day,
    required this.seq,
    required this.base,
    required this.tasks,
    required this.breaks,
    required this.gaps,
    required this.height,
  });

  final int day;

  /// Every row in time order with [TimelineItem.y] and [TimelineItem.h].
  final List<TimelineItem> seq;

  /// The untrimmed routine skeleton.
  final List<TimelineItem> base;

  /// Live tasks for the day, sorted by start.
  final List<Task> tasks;
  final List<TimelineItem> breaks;
  final List<TimelineItem> gaps;
  final double height;

  TimelineItem? rowForTask(String id) {
    for (final x in seq) {
      if (x.taskId == id) return x;
    }
    return null;
  }
}

/// Row height for an item (prototype `buildDay` heights).
double rowHeight(ItemKind k, int minutes) {
  final d = minutes * kPxPerMinute;
  switch (k) {
    case ItemKind.marker:
      return 30;
    case ItemKind.fixed:
      return minutes > 90 ? 58 : (d > 36 ? d : 36);
    case ItemKind.breakTime:
      return 22;
    case ItemKind.protected:
      return d > 28 ? d : 28;
    case ItemKind.task:
      return d > 44 ? d : 44;
    case ItemKind.open:
      return d > 36 ? d : 36;
  }
}

/// The day's timeline (prototype `buildDay`): tasks, auto breaks, protected
/// pieces trimmed around tasks, open gaps, and the proportional layout.
DayLayout buildDay(int day, Routine r, List<Task> all) {
  final base = baseItems(day, r);
  final ts = stableSorted(
      all.where((t) => t.day == day && t.isLive), (a, b) => a.start! - b.start!);

  // Auto break: 15 min after any task of 120 min or more, if free and not in
  // fixed time, and not past sleep.
  final brks = <TimelineItem>[];
  for (final t in ts) {
    if (t.end! - t.start! < 120) continue;
    final bs = t.end!, be = t.end! + 15;
    final clashTask = ts.any((o) => !identical(o, t) && o.start! < be && o.end! > bs);
    final clashFixed =
        base.any((x) => x.kind == ItemKind.fixed && x.start < be && x.end > bs);
    if (be <= r.sleep && !clashTask && !clashFixed) {
      brks.add(TimelineItem(
          id: 'brk_${t.id}',
          kind: ItemKind.breakTime,
          title: 'Break',
          start: bs,
          end: be,
          parentId: t.id));
    }
  }

  // Protected pieces are trimmed wherever a task or break overlaps them.
  final cover = <List<int>>[
    for (final t in ts) [t.start!, t.end!],
    for (final b in brks) [b.start, b.end],
  ];
  final items = <TimelineItem>[];
  for (final x in base) {
    if (x.kind != ItemKind.protected) {
      items.add(x);
      continue;
    }
    var pcs = <List<int>>[
      [x.start, x.end]
    ];
    for (final c in cover) {
      final cs = c[0], ce = c[1];
      pcs = [
        for (final p in pcs)
          if (ce <= p[0] || cs >= p[1])
            p
          else
            ...[
              [p[0], cs > p[0] ? cs : p[0]],
              [ce < p[1] ? ce : p[1], p[1]],
            ].where((q) => q[1] - q[0] >= 10),
      ];
    }
    for (var i = 0; i < pcs.length; i++) {
      items.add(x.copyWith(
          id: i == 0 ? x.id : '${x.id}_$i', start: pcs[i][0], end: pcs[i][1]));
    }
  }

  // Open gaps: all remaining time from wake to sleep of 10 min or more.
  final busy = stableSorted(<List<int>>[
    for (final x in items)
      if (x.kind != ItemKind.marker) [x.start, x.end],
    ...cover,
  ], (a, b) => a[0] - b[0]);
  final gaps = <TimelineItem>[];
  var c = r.wake;
  for (final b in busy) {
    if (b[0] - c >= 10) {
      gaps.add(TimelineItem(
          id: 'gap$c', kind: ItemKind.open, title: 'Open', start: c, end: b[0]));
    }
    if (b[1] > c) c = b[1];
  }
  if (r.sleep - c >= 10) {
    gaps.add(TimelineItem(
        id: 'gap$c', kind: ItemKind.open, title: 'Open', start: c, end: r.sleep));
  }

  int rank(TimelineItem x) => x.id == 'wake' ? -1 : (x.id == 'sleep' ? 1 : 0);
  final taskRows = [
    for (final t in ts)
      TimelineItem(
          id: t.id,
          kind: ItemKind.task,
          title: t.title,
          cat: t.cat,
          start: t.start!,
          end: t.end!,
          taskId: t.id),
  ];
  final seq = stableSorted([...items, ...taskRows, ...brks, ...gaps], (a, b) {
    final d = a.start - b.start;
    return d != 0 ? d : rank(a) - rank(b);
  });

  var y = 0.0;
  final laid = <TimelineItem>[];
  for (final it in seq) {
    final h = rowHeight(it.kind, it.end - it.start);
    laid.add(it.copyWith(y: y, h: h));
    y += h + kRowGap;
  }
  return DayLayout(
      day: day,
      seq: laid,
      base: base,
      tasks: ts,
      breaks: brks,
      gaps: gaps,
      height: y);
}

/// Y offset of [now] inside a laid-out day (prototype `nowY`).
double nowY(List<TimelineItem> seq, double now) {
  for (final x in seq) {
    if (x.kind != ItemKind.marker && now >= x.start && now < x.end) {
      return x.y + (now - x.start) / (x.end - x.start) * x.h;
    }
  }
  for (final x in seq) {
    if (x.start >= now) return x.y;
  }
  return seq.isEmpty ? 0 : seq.last.y;
}
