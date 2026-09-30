import 'base_day.dart';
import 'capacity.dart';
import 'category.dart';
import 'routine.dart';
import 'task.dart';
import 'time.dart';

/// A half-open busy interval [start, end).
typedef Interval = (int, int);

/// Time-of-day preference for [findSlot].
enum TimePref { any, morning, afternoon, evening }

class Slot {
  const Slot(this.start, this.end, {this.overWindDown = false});
  final int start, end;

  /// True when the slot only fits by spilling into wind-down.
  final bool overWindDown;
  @override
  String toString() => 'Slot(${fmt(start)}-${fmt(end)}${overWindDown ? ' wind' : ''})';
}

class DaySlot extends Slot {
  const DaySlot(this.day, super.start, super.end, {super.overWindDown});
  final int day;
}

/// Whether a live task counts as missed: not done and its end has passed
/// (today), or its day is past.
bool isMissed(Task t, int today, num now) =>
    t.isLive &&
    !t.done &&
    (t.day! < today || (t.day == today && t.end! <= now));

/// Busy intervals for [day] (prototype `busyOf`): fixed and protected time
/// (wind-down excluded only when [allowWindDown]) plus other live tasks, each
/// extended by 15 min when 120 min or longer.
List<Interval> busyOf(int day, Routine r, List<Task> all,
    {String? exclude, bool allowWindDown = false}) {
  final iv = <Interval>[];
  for (final x in baseItems(day, r)) {
    if (x.kind == ItemKind.fixed) iv.add((x.start, x.end));
    if (x.kind == ItemKind.protected && !(allowWindDown && x.id == 'wind')) {
      iv.add((x.start, x.end));
    }
  }
  for (final t in all) {
    if (t.day != day || !t.isLive || t.id == exclude) continue;
    final len = t.end! - t.start!;
    iv.add((t.start!, t.end! + (len >= 120 ? 15 : 0)));
  }
  return iv;
}

/// Walks forward past every overlapping interval (prototype `earliestFree`).
/// Returns the first start where [duration] fits before [limit], or null.
int? earliestFree(List<Interval> iv, int from, int duration, int limit) {
  var x = from;
  var moved = true;
  var n = 0;
  while (moved && n++ < 60) {
    moved = false;
    for (final (a, b) in iv) {
      if (a < x + duration && b > x) {
        x = b;
        moved = true;
      }
    }
  }
  return x + duration <= limit ? x : null;
}

/// Preference start minute (morning 09:00, afternoon 13:00, evening 18:00,
/// weekend default 10:00, or an exact time).
int prefStart(int day, TimePref pref, int? at) {
  if (at != null) return at;
  return switch (pref) {
    TimePref.morning => 540,
    TimePref.afternoon => 780,
    TimePref.evening => 1080,
    TimePref.any => isWeekend(day) ? 600 : 0,
  };
}

/// Finds time for [duration] minutes on [day] (prototype `findSlot`).
/// Tries from the preference, then from [after]; with [allowWindDown] it
/// retries with wind-down open as a last resort.
Slot? findSlot(
  int day,
  int duration,
  Routine r,
  List<Task> all, {
  int after = 0,
  TimePref pref = TimePref.any,
  int? at,
  String? exclude,
  bool allowWindDown = false,
}) {
  final lo = r.wake > after ? r.wake : after;
  final pf = prefStart(day, pref, at);
  final tries = [pf > lo ? pf : lo, lo];
  for (final wind in allowWindDown ? const [false, true] : const [false]) {
    final iv = busyOf(day, r, all, exclude: exclude, allowWindDown: wind);
    for (final f in tries) {
      final x = earliestFree(iv, ceil5(f), duration, r.sleep);
      if (x != null) return Slot(x, x + duration, overWindDown: wind);
    }
  }
  return null;
}

/// Snaps a drag position to the board (prototype `wMove`): 15-minute grid,
/// clamped to wake…sleep−duration, and never before now on today.
int snapDrop(int rawStart, int duration, Routine r,
    {required bool isToday, num now = 0}) {
  var st = (rawStart / 15).round() * 15;
  st = clampInt(st, r.wake, r.sleep - duration);
  if (isToday) {
    final n = ceil5(now);
    if (n > st) st = n;
  }
  return st;
}

/// Moves task [id] to [day] at [start] and reflows that day's other undone
/// tasks (prototype `ripple`). A drop onto fixed or protected time slides to
/// the next free boundary; done tasks never move; every other undone task
/// keeps its start if free, otherwise slides to the earliest free start
/// after it. Returns the whole updated list.
List<Task> ripple(List<Task> all, String id, int day, int start, Routine r) {
  final t = all.firstWhere((x) => x.id == id);
  if (t.done || !t.isScheduled) return all;
  final dd = t.end! - t.start!;
  final baseIv = busyOf(day, r, const []);
  final st = earliestFree(baseIv, start, dd, r.sleep + 180) ?? start;
  final moved = t.placed(day, st, st + dd);
  final occ = [...baseIv, (moved.start!, moved.end! + (dd >= 120 ? 15 : 0))];
  for (final x in all) {
    if (x.id != id && x.day == day && x.isLive && x.done) {
      occ.add((x.start!, x.end!));
    }
  }
  final upd = <String, (int, int)>{};
  final others = stableSorted(
      all.where((x) => x.id != id && x.day == day && x.isLive && !x.done),
      (a, b) => a.start! - b.start!);
  for (final o in others) {
    final od = o.end! - o.start!;
    final ns = earliestFree(occ, o.start!, od, 99999)!;
    upd[o.id] = (ns, ns + od);
    occ.add((ns, ns + od + (od >= 120 ? 15 : 0)));
  }
  return [
    for (final x in all)
      if (x.id == id)
        moved
      else if (upd.containsKey(x.id))
        x.copyWith(start: upd[x.id]!.$1, end: upd[x.id]!.$2)
      else
        x
  ];
}

/// How many other tasks a ripple displaced ("3 blocks made room").
int ripplePushed(List<Task> before, List<Task> after, String movedId) {
  final byId = {for (final t in before) t.id: t};
  var n = 0;
  for (final x in after) {
    final o = byId[x.id];
    if (x.id != movedId && o != null && (o.start != x.start || o.day != x.day)) {
      n++;
    }
  }
  return n;
}

/// A task to place, as spoken or typed.
class TaskSpec {
  const TaskSpec({
    required this.title,
    required this.cat,
    required this.duration,
    this.day,
    this.pref,
    this.at,
    this.existingId,
  });
  final String title;
  final Category cat;
  final int duration;

  /// Target epoch day; null lets the caller decide.
  final int? day;
  final TimePref? pref;
  final int? at;

  /// When placing an inbox task, its id.
  final String? existingId;
}

class Placement {
  const Placement(this.task, this.slot, this.day);
  final Task task;
  final Slot slot;
  final int day;
}

class PlaceResult {
  const PlaceResult(this.tasks, this.placed, this.left);

  /// The whole updated task list.
  final List<Task> tasks;
  final List<Placement> placed;
  final List<TaskSpec> left;
}

/// Places several tasks in the order given, each after the previous one on
/// the same day (voice multi-task, "Add gym", "Plan my evening").
///
/// * [allowWindDown]: spill into wind-down as a last resort, so the UI can
///   offer "Move / Keep anyway" (the three-task request).
/// * [searchForward]: when [TaskSpec.day] is full, try the next 6 days
///   ("Add gym tomorrow" when tomorrow is full).
/// * [capacityLimited]: stop placing on a day once realistic capacity runs
///   out ("Plan my evening"); leftovers are returned in [PlaceResult.left].
PlaceResult placeMany(
  List<TaskSpec> specs,
  List<Task> all,
  Routine r, {
  required int today,
  required num now,
  required String Function() newId,
  bool allowWindDown = false,
  bool searchForward = false,
  bool capacityLimited = false,
  DateTime? createdAt,
}) {
  var tasks = List<Task>.of(all);
  final placed = <Placement>[];
  final left = <TaskSpec>[];
  final lastEnd = <int, int>{};
  for (final sp in specs) {
    var day = sp.day ?? today;
    int afterFor(int d) {
      final a = d == today ? ceil5(now) : 0;
      final p = lastEnd[d] ?? 0;
      return a > p ? a : p;
    }

    TimePref prefFor(int d) =>
        sp.pref ?? (isWeekend(d) ? TimePref.any : TimePref.evening);
    var sl = findSlot(day, sp.duration, r, tasks,
        after: afterFor(day),
        pref: prefFor(day),
        at: sp.at,
        exclude: sp.existingId,
        allowWindDown: allowWindDown);
    if (sl == null && searchForward) {
      for (var d = day + 1; d < day + 7; d++) {
        sl = findSlot(d, sp.duration, r, tasks,
            after: afterFor(d), pref: TimePref.evening, exclude: sp.existingId);
        if (sl != null) {
          day = d;
          break;
        }
      }
    }
    if (sl == null) {
      left.add(sp);
      continue;
    }
    final Task nt;
    if (sp.existingId != null) {
      nt = tasks
          .firstWhere((t) => t.id == sp.existingId)
          .copyWith(day: day, start: sl.start, end: sl.end, source: Source.voice);
    } else {
      nt = Task.make(newId(), sp.title, sp.cat, day, sl.start, sp.duration,
          source: Source.voice, createdAt: createdAt);
    }
    final next = sp.existingId != null
        ? [for (final t in tasks) t.id == sp.existingId ? nt : t]
        : [...tasks, nt];
    if (capacityLimited) {
      final c = capOf(day, r, next, day == today ? now : 0);
      if (c.planned > c.realistic) {
        left.add(sp);
        continue;
      }
    }
    tasks = next;
    lastEnd[day] = sl.end;
    placed.add(Placement(nt, sl, day));
  }
  return PlaceResult(tasks, placed, left);
}

/// The block the over-capacity row offers to move on Today (prototype
/// `overTaskOf`): the latest undone task that runs into wind-down, else the
/// latest one.
Task? overTaskOf(int day, Routine r, List<Task> all) {
  final ts = stableSorted(all.where((t) => t.day == day && t.isLive && !t.done),
      (a, b) => b.start! - a.start!);
  if (ts.isEmpty) return null;
  for (final t in ts) {
    if (t.end! > r.sleep - 30) return t;
  }
  return ts.first;
}

class MoveSuggestion {
  const MoveSuggestion(this.task, this.day, this.slot);
  final Task task;
  final int day;
  final Slot slot;
}

/// Today's "Move `<task>`" (prototype `moveOver`): sends [overTaskOf] to the
/// next day with an evening slot.
MoveSuggestion? moveOverToday(int day, Routine r, List<Task> all) {
  final t = overTaskOf(day, r, all);
  if (t == null) return null;
  final len = t.end! - t.start!;
  for (var nd = day + 1; nd < day + 7; nd++) {
    final sl = findSlot(nd, len, r, all, exclude: t.id, pref: TimePref.evening);
    if (sl != null) return MoveSuggestion(t, nd, sl);
  }
  return null;
}

/// The Plan board's "Move one" (prototype `moveOverGeneric`): picks the block
/// that best covers the overflow and sends it to the next lighter day's first
/// fitting slot, up to [lastDay] (the end of the displayed week).
///
/// Deviation, deliberate: the prototype's `find` over a longest-first sort
/// always returns the longest block. README 5.5 asks for the block that
/// *best covers* the overflow, so this takes the shortest block that is at
/// least as long as the overflow, falling back to the longest. It also
/// prefers a target day that stays within its realistic time.
MoveSuggestion? moveOneBlock(int day, Routine r, List<Task> all,
    {required int today, required num now, required int lastDay}) {
  final c = capOf(day, r, all, day == today ? now : 0);
  if (c.over <= 0) return null;
  final ts = stableSorted(
      all.where((t) =>
          t.day == day &&
          t.isLive &&
          !t.done &&
          (day != today || t.start! >= now)),
      (a, b) => (a.end! - a.start!) - (b.end! - b.start!));
  if (ts.isEmpty) return null;
  final t = ts.firstWhere((x) => x.end! - x.start! >= c.over, orElse: () => ts.last);
  final len = t.end! - t.start!;
  MoveSuggestion? fallback;
  for (var nd = day + 1; nd <= lastDay; nd++) {
    final pref = isWeekend(nd) ? TimePref.morning : TimePref.evening;
    final sl = findSlot(nd, len, r, all, exclude: t.id, pref: pref);
    if (sl == null) continue;
    final trial = [
      for (final x in all) x.id == t.id ? x.placed(nd, sl.start, sl.end) : x
    ];
    final after = capOf(nd, r, trial, nd == today ? now : 0);
    final m = MoveSuggestion(t, nd, sl);
    if (!after.isOver) return m;
    fallback ??= m;
  }
  return fallback;
}

enum RescheduleOptionKind { laterToday, tomorrow, thisWeekend }

class RescheduleOption {
  const RescheduleOption(this.kind, this.label, this.day, this.slot, this.text);
  final RescheduleOptionKind kind;
  final String label;
  final int day;
  final Slot? slot;

  /// The scheduler's real answer: "Tomorrow 21:00", "Sat 09:00", "No room".
  final String text;
  bool get ok => slot != null;
}

String _relDay(int d, int today) => d == today
    ? 'Today'
    : d == today + 1
        ? 'Tomorrow'
        : dayShortNames[weekday0(d)];

/// The DecisionSheet's options (prototype `reOptions`).
List<RescheduleOption> rescheduleOptions(
    Task t, Routine r, List<Task> all, {required int today, required num now}) {
  final len = t.end! - t.start!;
  RescheduleOption mk(RescheduleOptionKind k, String label, int d,
      {int after = 0, TimePref pref = TimePref.any}) {
    final sl = findSlot(d, len, r, all, exclude: t.id, after: after, pref: pref);
    return RescheduleOption(
        k, label, d, sl, sl != null ? '${_relDay(d, today)} ${fmt(sl.start)}' : 'No room');
  }

  final tom = today + 1;
  final later = mk(RescheduleOptionKind.laterToday, 'Later today', today,
      after: ceil5(now));
  return [
    later.ok
        ? later
        : RescheduleOption(later.kind, later.label, today, null, 'No room left today'),
    mk(RescheduleOptionKind.tomorrow, 'Tomorrow', tom,
        pref: isWeekend(tom) ? TimePref.morning : TimePref.evening),
    mk(RescheduleOptionKind.thisWeekend, 'This weekend', weekendTarget(today),
        pref: TimePref.morning),
  ];
}

/// "This weekend": Saturday on weekdays, Sunday on Saturday, next Saturday
/// on Sunday.
int weekendTarget(int today) {
  final w = weekday0(today);
  if (w < 5) return today + (5 - w);
  if (w == 5) return today + 1;
  return today + 6;
}

/// "Choose a day": the first fitting time on each of the next 7 days.
List<(int, Slot?)> chooseDaySlots(
    Task t, Routine r, List<Task> all, {required int today, required num now}) {
  final len = t.end! - t.start!;
  return [
    for (var i = 0; i < 7; i++)
      (
        today + i,
        findSlot(today + i, len, r, all,
            exclude: t.id, after: i == 0 ? ceil5(now) : 0)
      )
  ];
}

/// The TaskSheet's live preview (prototype `previewSlot`): the chosen day, or
/// every day of the next week, first without wind-down, then with it.
DaySlot? previewSlot(
  int duration,
  Routine r,
  List<Task> all, {
  required int today,
  required num now,
  int? date,
  TimePref pref = TimePref.any,
  int? at,
  String? editId,
}) {
  final days = date != null ? [date] : [for (var i = 0; i < 7; i++) today + i];
  for (final wind in const [false, true]) {
    for (final d in days) {
      final sl = findSlot(d, duration, r, all,
          exclude: editId,
          pref: pref,
          at: at,
          after: d == today ? ceil5(now) : 0,
          allowWindDown: wind);
      if (sl != null) {
        return DaySlot(d, sl.start, sl.end, overWindDown: sl.overWindDown);
      }
    }
  }
  return null;
}

/// "Fit in" for an Unscheduled task (prototype `fitIn`).
DaySlot? fitInSlot(Task t, Routine r, List<Task> all,
    {required int today, required num now}) {
  for (var d = today; d < today + 7; d++) {
    final sl = findSlot(d, t.duration, r, all,
        exclude: t.id,
        after: d == today ? ceil5(now) : 0,
        pref: isWeekend(d) ? TimePref.morning : TimePref.evening);
    if (sl != null) return DaySlot(d, sl.start, sl.end);
  }
  return null;
}

class RescheduleResult {
  const RescheduleResult(this.tasks, this.moves);
  final List<Task> tasks;

  /// (original task, new day, new slot)
  final List<(Task, int, Slot)> moves;
}

/// "Reschedule unfinished tasks": every missed task goes to its next free
/// slot within a week, counting as a reschedule.
RescheduleResult rescheduleUnfinished(List<Task> all, Routine r,
    {required int today, required num now}) {
  final miss = all.where((t) => isMissed(t, today, now)).toList();
  var tasks = List<Task>.of(all);
  final moves = <(Task, int, Slot)>[];
  for (final m in miss) {
    final len = m.end! - m.start!;
    for (var d = today; d < today + 7; d++) {
      final sl = findSlot(d, len, r, tasks,
          exclude: m.id, after: d == today ? ceil5(now) : 0);
      if (sl != null) {
        tasks = [
          for (final t in tasks)
            t.id == m.id
                ? t.copyWith(
                    day: d,
                    start: sl.start,
                    end: sl.end,
                    movedCount: t.movedCount + 1)
                : t
        ];
        moves.add((m, d, sl));
        break;
      }
    }
  }
  return RescheduleResult(tasks, moves);
}

/// Completing a task (prototype `toggle`). When finished during its block,
/// the end moves to now (rounded up to 5 min, at least 15 min in) and the
/// minutes handed back are returned. Returns (updated task, minutes back).
(Task, int) completeTask(Task t, {required int today, required num now}) {
  final isNow = t.day == today && now >= t.start! && now < t.end!;
  var early = 0;
  if (isNow) {
    final minEnd = t.start! + 15;
    final c = ceil5(now);
    final v = (t.end! - (minEnd > c ? minEnd : c)).round();
    early = v > 0 ? v : 0;
  }
  var nt = t.copyWith(done: true, doneAt: now.floor());
  if (early >= 5) nt = nt.copyWith(plannedEnd: t.end, end: t.end! - early);
  return (nt, early >= 5 ? early : 0);
}

/// "Mark not done": restores the planned end.
Task uncompleteTask(Task t) => t.copyWith(
    done: false, end: t.plannedEnd ?? t.end, plannedEnd: null, doneAt: null);

/// After a routine change ("Planner rebuilt your week around it"): from
/// [today] on, every undone task that has not started keeps its start if it
/// is still free, otherwise slides to the earliest free start after it
/// (never before wake or into fixed or protected time; a kept overflow may
/// stay in wind-down). Done and already-started tasks stay put. Unchanged
/// tasks are returned as the same instances.
List<Task> reflowForRoutine(List<Task> all, Routine r, int today, num now) {
  bool pinned(Task t) => t.done || (t.day == today && t.start! < now);
  final days = stableSorted(
      {for (final t in all) if (t.isLive && !pinned(t) && t.day! >= today) t.day!}.toList(),
      (a, b) => a - b);
  final upd = <String, (int, int)>{};
  for (final day in days) {
    final occ = <Interval>[(0, r.wake), ...busyOf(day, r, const [], allowWindDown: true)];
    for (final x in all) {
      if (x.day == day && x.isLive && pinned(x)) {
        final len = x.end! - x.start!;
        occ.add((x.start!, x.end! + (len >= 120 ? 15 : 0)));
      }
    }
    final movable = stableSorted(
        all.where((x) => x.day == day && x.isLive && !pinned(x)), (a, b) => a.start! - b.start!);
    for (final o in movable) {
      final od = o.end! - o.start!;
      final ns = earliestFree(occ, o.start!, od, 99999)!;
      if (ns != o.start) upd[o.id] = (ns, ns + od);
      occ.add((ns, ns + od + (od >= 120 ? 15 : 0)));
    }
  }
  if (upd.isEmpty) return all;
  return [
    for (final x in all)
      if (upd[x.id] case (final s, final e)) x.copyWith(start: s, end: e) else x
  ];
}
