import 'category.dart';
import 'routine.dart';
import 'time.dart';

/// Timeline item kinds (prototype `k`): marker, fixed, prot(ected), break,
/// task, open.
enum ItemKind { marker, fixed, protected, breakTime, task, open }

/// A derived timeline item. Never stored. [y] and [h] are filled in by
/// `buildDay`'s proportional layout; base items leave them at 0.
class TimelineItem {
  const TimelineItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.start,
    required this.end,
    this.cat,
    this.taskId,
    this.parentId,
    this.y = 0,
    this.h = 0,
  });

  final String id;
  final ItemKind kind;
  final String title;
  final int start, end;
  final Category? cat;

  /// Set for task rows (prototype `tid`).
  final String? taskId;

  /// Set for auto breaks: the task they follow.
  final String? parentId;
  final double y, h;

  int get length => end - start;

  TimelineItem copyWith({String? id, int? start, int? end, double? y, double? h}) =>
      TimelineItem(
        id: id ?? this.id,
        kind: kind,
        title: title,
        start: start ?? this.start,
        end: end ?? this.end,
        cat: cat,
        taskId: taskId,
        parentId: parentId,
        y: y ?? this.y,
        h: h ?? this.h,
      );

  @override
  String toString() => '${kind.name}($id "$title" ${fmt(start)}-${fmt(end)})';
}

/// Whether [day] runs the fixed work block.
bool isWorkDay(int day, Routine r) => weekday0(day) < 5 && !r.noFixedWork;

/// The routine's skeleton for one day (prototype `baseItems`):
/// Wake and Sleep markers, Getting ready, Office, commitments and Wind-down.
/// Overlaps resolve in time order: a later item starts at the previous one's
/// end and is dropped if under 10 minutes.
List<TimelineItem> baseItems(int day, Routine r) {
  final wk = isWorkDay(day, r);
  final out = <TimelineItem>[];
  final ready = wk ? r.workStart : r.wake + 60;
  if (ready > r.wake) {
    out.add(TimelineItem(
        id: 'morn',
        kind: ItemKind.protected,
        title: 'Getting ready',
        start: r.wake,
        end: ready));
  }
  if (wk) {
    out.add(TimelineItem(
        id: 'work',
        kind: ItemKind.fixed,
        cat: Category.work,
        title: 'Office',
        start: r.workStart,
        end: r.workEnd));
  }
  for (final c in r.commitments) {
    if (!c.on || !c.days.matches(day)) continue;
    out.add(TimelineItem(
        id: 'c_${c.id}',
        kind: ItemKind.fixed,
        cat: c.cat,
        title: c.title,
        start: c.start,
        end: c.end));
  }
  out.add(TimelineItem(
      id: 'wind',
      kind: ItemKind.protected,
      title: 'Wind-down',
      start: r.sleep - 30,
      end: r.sleep));
  final sorted = stableSorted(out, (a, b) => a.start - b.start);
  final res = <TimelineItem>[];
  var end = r.wake;
  for (final x in sorted) {
    final s = x.start > end ? x.start : end;
    final e = x.end < r.sleep ? x.end : r.sleep;
    if (e - s >= 10) {
      res.add(x.copyWith(start: s, end: e));
      end = e;
    }
  }
  return [
    TimelineItem(
        id: 'wake',
        kind: ItemKind.marker,
        title: 'Wake',
        start: r.wake,
        end: r.wake),
    ...res,
    TimelineItem(
        id: 'sleep',
        kind: ItemKind.marker,
        title: 'Sleep',
        start: r.sleep,
        end: r.sleep),
  ];
}
