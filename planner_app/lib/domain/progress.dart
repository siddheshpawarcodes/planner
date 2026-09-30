import 'base_day.dart';
import 'category.dart';
import 'routine.dart';
import 'scheduler.dart';
import 'task.dart';
import 'time.dart';

/// Ribbon band order (README 6.8): Study, Build, Body, People, Self, Rest,
/// then Work when "With work" is on.
const ribbonOrder = [
  Category.study,
  Category.build,
  Category.body,
  Category.people,
  Category.self,
  Category.rest,
  Category.work,
];

/// "Focused" time: the hours chosen for yourself, outside work.
const focusCats = {Category.study, Category.build, Category.self};

/// Heatmap: 36 half-hour cells from 06:00 to 24:00.
const kHeatStart = 360;
const kHeatCells = 36;

/// Heat level 0-4 for focused minutes in a half-hour cell; drawn at
/// 0 / .18 / .36 / .62 / 1 of `tx`.
int heatLevel(int minutes) => minutes <= 0
    ? 0
    : minutes <= 8
        ? 1
        : minutes <= 15
            ? 2
            : minutes <= 22
                ? 3
                : 4;

const heatOpacity = [0.0, 0.18, 0.36, 0.62, 1.0];

/// The best two-hour window (4 cells) across the week.
class BestWindow {
  const BestWindow(this.cell, this.minutes, this.days);

  /// First cell of the window.
  final int cell;
  final int minutes;

  /// Days with focused time inside the window.
  final int days;

  int get start => kHeatStart + cell * 30;
  int get end => start + 120;
}

/// Everything Progress and the weekly review show, for the week containing
/// `today`. Pure: derived from tasks, the routine and the clock.
class WeekProgress {
  WeekProgress._({
    required this.weekStart,
    required this.today,
    required this.firstDay,
    required this.completed,
    required this.planned,
    required this.work,
    required this.plannedTasks,
    required this.doneTasks,
    required this.rescheduled,
    required this.skipped,
    required this.carried,
    required this.heat,
    required this.best,
  });

  final int weekStart, today;

  /// The first day Planner was in use this week (install day or Monday).
  final int firstDay;

  /// Completed minutes per category per day (index 0 = Monday): finished
  /// tasks plus fixed time that has passed.
  final Map<Category, List<int>> completed;

  /// The planned envelope per day, work excluded: live tasks plus fixed
  /// commitments, for days up to today.
  final List<int> planned;

  /// Office minutes per day up to today (added to the envelope "With work").
  final List<int> work;

  /// Tasks planned this week up to today (skipped ones only when they count
  /// as missed), and the ones finished, in time order.
  final List<Task> plannedTasks, doneTasks;
  final List<Task> rescheduled, skipped, carried;

  /// Focused minutes per weekday row and half-hour cell.
  final List<List<int>> heat;
  final BestWindow? best;

  int get plannedCount => plannedTasks.length;
  int get doneCount => doneTasks.length;
  int get percent => plannedCount == 0 ? 0 : (doneCount * 100 / plannedCount).round();

  /// Days with Planner this week, up to today.
  int get daysWithPlanner => today - firstDay + 1;

  bool beforePlanner(int i) => weekStart + i < firstDay;

  List<Category> cats({required bool withWork}) =>
      withWork ? ribbonOrder : ribbonOrder.where((c) => c != Category.work).toList();

  /// Completed minutes on day [i] across the shown categories.
  int dayTotal(int i, {required bool withWork}) =>
      cats(withWork: withWork).fold(0, (a, c) => a + completed[c]![i]);

  int envelope(int i, {required bool withWork}) => planned[i] + (withWork ? work[i] : 0);

  int catTotal(Category c) => completed[c]!.fold(0, (a, v) => a + v);

  int get focusedMinutes => focusCats.fold(0, (a, c) => a + catTotal(c));

  /// Weekly totals, largest first, zero categories left out.
  List<(Category, int)> totals({required bool withWork}) {
    final l = [
      for (final c in cats(withWork: withWork))
        if (catTotal(c) > 0) (c, catTotal(c))
    ];
    return stableSorted(l, (a, b) => b.$2 - a.$2);
  }

  /// Categories on day [i], largest first.
  List<(Category, int)> dayBreakdown(int i, {required bool withWork}) {
    final l = [
      for (final c in cats(withWork: withWork))
        if (completed[c]![i] > 0) (c, completed[c]![i])
    ];
    return stableSorted(l, (a, b) => b.$2 - a.$2);
  }

  /// The category with the most completed task time (Rest and Work aside).
  (Category, int)? get mostActive {
    (Category, int)? m;
    for (final c in ribbonOrder) {
      if (c == Category.rest || c == Category.work) continue;
      final v = catTotal(c);
      if (v > 0 && (m == null || v > m.$2)) m = (c, v);
    }
    return m;
  }

  /// The day with the most of your time (work aside).
  (int, int)? get biggestDay {
    (int, int)? m;
    for (var i = 0; i < 7; i++) {
      final v = dayTotal(i, withWork: false);
      if (v > 0 && (m == null || v > m.$2)) m = (i, v);
    }
    return m;
  }

  /// The day with the most unfinished planned time.
  (int, int)? get mostUnfinished {
    (int, int)? m;
    for (var i = 0; i < 7; i++) {
      final v = planned[i] - dayTotal(i, withWork: false);
      if (v > 0 && (m == null || v > m.$2)) m = (i, v);
    }
    return m;
  }
}

/// Aggregates the week containing [today] (Monday start).
WeekProgress weekProgress({
  required List<Task> tasks,
  required Routine routine,
  required int today,
  required num now,
  int? installedDay,
  bool countSkippedAsMissed = false,
}) {
  final ws = weekStart(today);
  final first = installedDay == null ? ws : clampInt(installedDay, ws, today);
  final completed = {for (final c in Category.values) c: List.filled(7, 0)};
  final planned = List.filled(7, 0), work = List.filled(7, 0);
  final heat = List.generate(7, (_) => List.filled(kHeatCells, 0));

  final week = [
    for (final t in tasks)
      if (!t.deleted && t.day != null && t.start != null && t.day! >= ws && t.day! <= today) t
  ]..sort((a, b) => a.day != b.day ? a.day! - b.day! : a.start! - b.start!);

  for (final t in week) {
    final i = t.day! - ws;
    final len = t.end! - t.start!;
    if (!t.skipped) planned[i] += len;
    if (!t.done) continue;
    completed[t.cat]![i] += len;
    if (!focusCats.contains(t.cat)) continue;
    for (var c = 0; c < kHeatCells; c++) {
      final a = kHeatStart + c * 30, b = a + 30;
      final o = (t.end! < b ? t.end! : b) - (t.start! > a ? t.start! : a);
      if (o > 0) heat[i][c] += o;
    }
  }

  // Fixed time that has passed counts as lived; commitments join the plan.
  for (var d = first; d <= today; d++) {
    final i = d - ws;
    for (final x in baseItems(d, routine)) {
      if (x.kind != ItemKind.fixed) continue;
      final len = x.end - x.start;
      final lived = d < today ? len : clampInt(now.floor() - x.start, 0, len);
      completed[x.cat!]![i] += lived;
      if (x.cat == Category.work) {
        work[i] += len;
      } else {
        planned[i] += len;
      }
    }
  }

  BestWindow? best;
  for (var c = 0; c + 4 <= kHeatCells; c++) {
    var m = 0, days = 0;
    for (var r = 0; r < 7; r++) {
      final v = heat[r][c] + heat[r][c + 1] + heat[r][c + 2] + heat[r][c + 3];
      m += v;
      if (v > 0) days++;
    }
    if (m > 0 && (best == null || m > best.minutes)) best = BestWindow(c, m, days);
  }

  final counted = [
    for (final t in week)
      if (!t.skipped || countSkippedAsMissed) t
  ];
  return WeekProgress._(
    weekStart: ws,
    today: today,
    firstDay: first,
    completed: completed,
    planned: planned,
    work: work,
    plannedTasks: counted,
    doneTasks: [for (final t in week) if (t.done) t],
    rescheduled: [for (final t in week) if (t.movedCount > 0) t],
    skipped: [for (final t in week) if (t.skipped) t],
    carried: [for (final t in week) if (isMissed(t, today, now)) t],
    heat: heat,
    best: best,
  );
}

/// The Review button shows on Sunday evening.
bool reviewAvailable(int today, num now) => weekday0(today) == 6 && now >= 1080;

// ------------------------------------------------------------------ copy

const _numberWords = ['zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten'];

/// "five" (numbers up to ten are written out).
String numberWord(int n) => n >= 0 && n < _numberWords.length ? _numberWords[n] : '$n';

String capitalised(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

String plural(int n, String one, [String? many]) => n == 1 ? one : (many ?? '${one}s');

/// "Exercise", "Exercise and Flutter", "Exercise, Flutter and 2 more".
String nameList(List<String> names) {
  if (names.isEmpty) return '';
  if (names.length == 1) return names.first;
  if (names.length == 2) return '${names[0]} and ${names[1]}';
  return '${names[0]}, ${names[1]} and ${names.length - 2} more';
}

/// Progress › the sentence under the hero count.
String progressSubline(WeekProgress p, {required bool weekDone}) {
  if (p.plannedCount == 0) {
    return 'Tell Planner what you want to accomplish. The ribbon fills in as you do it.';
  }
  if (!weekDone) return 'The ribbon fills in as the week happens.';
  if (p.doneCount == p.plannedCount) return 'Everything you planned landed.';
  final u = p.mostUnfinished;
  if (u != null && u.$2 >= 60) {
    return 'Most of the unfinished time was ${dayLongNames[u.$1]}. Everything else landed.';
  }
  return 'Most of what you planned landed.';
}

/// "Most productive 20:30 → 22:30, five days out of six".
String heatSummary(WeekProgress p) {
  final b = p.best;
  if (b == null || p.daysWithPlanner < 3) return 'Your rhythm appears here after a few days of use.';
  return 'Most productive ${fmt(b.start)} → ${fmt(b.end)}, '
      '${numberWord(b.days)} ${plural(b.days, 'day')} out of ${numberWord(p.daysWithPlanner)}';
}

/// "Thu 21:00 → 21:30: 22m focused"
String heatCellText(WeekProgress p, int row, int cell) {
  final m = kHeatStart + cell * 30;
  return '${dayShortNames[row]} ${fmt(m)} → ${fmt(m + 30)}: ${dur(p.heat[row][cell])} focused';
}

/// Review › screen 1.
String reviewIntro(WeekProgress p) {
  final n = p.daysWithPlanner;
  final lead = n >= 7 ? 'A full week with Planner.' : '${capitalised(numberWord(n))} ${plural(n, 'day')} with Planner.';
  return '$lead Each band is a category. Thicker means more of your time went there.';
}

/// Review › screen 2 sentence.
String reviewCompletion(WeekProgress p, {required bool firstWeek}) {
  if (p.plannedCount == 0) return 'Nothing was planned this week. Next week starts fresh.';
  final open = p.plannedCount - p.doneCount;
  final lead = '${p.percent}% completion ${firstWeek ? 'in your first week' : 'this week'}.';
  if (open == 0) return '$lead Every square filled in.';
  final sq = open == 1 ? 'The open square was' : 'The ${numberWord(open)} open squares were';
  return '$lead $sq moved or skipped, not lost.';
}

/// Review › screen 4 rows: (label, count, detail).
List<(String, int, String)> reviewMoves(WeekProgress p) {
  List<String> names(List<Task> l) {
    final seen = <String>{};
    return [for (final t in l) if (seen.add(t.title)) t.title];
  }

  final r = names(p.rescheduled), s = names(p.skipped), c = names(p.carried);
  return [
    (
      'Rescheduled',
      p.rescheduled.length,
      r.isEmpty ? 'Everything happened when planned' : '${nameList(r)} found ${r.length == 1 ? 'a new time' : 'new times'}'
    ),
    ('Skipped', p.skipped.length, s.isEmpty ? 'Nothing was skipped' : nameList(s)),
    (
      'Carried forward',
      p.carried.length,
      c.isEmpty ? 'Nothing carries over' : '${nameList(c)} ${c.length == 1 ? 'moves' : 'move'} into next week'
    ),
  ];
}

/// Review › screen 5 title and sentence.
(String, String) reviewBestHours(WeekProgress p) {
  final b = p.best;
  if (b == null) {
    return ('Your rhythm is still forming.', 'A few more days of use and Planner will know your best hours.');
  }
  final part = b.start >= 1020 ? 'evening' : (b.start < 720 ? 'morning' : 'afternoon');
  final days = '${capitalised(numberWord(b.days))} ${plural(b.days, part)} out of ${numberWord(p.daysWithPlanner)}.';
  return ('Your best hours were ${fmt(b.start)} → ${fmt(b.end)}.', '$days Planner will put demanding work there first.');
}

/// Review › screen 6 sentence.
String reviewAhead(int carried, int deadlines) {
  final a = carried == 0
      ? 'Nothing carries into next week.'
      : '${capitalised(numberWord(carried))} ${carried == 1 ? 'task carries' : 'tasks carry'} into next week.';
  final b = deadlines == 0
      ? 'No deadlines are on the way.'
      : '${capitalised(numberWord(deadlines))} ${deadlines == 1 ? 'deadline is' : 'deadlines are'} on the way.';
  return '$a $b';
}

/// The note after "Plan next week".
String planNextNote(int carried, int deadlines) {
  if (carried == 0 && deadlines == 0) return 'Next week starts clear.';
  final parts = [
    if (carried > 0) '$carried carried-forward ${plural(carried, 'task')}',
    if (deadlines > 0) '$deadlines ${plural(deadlines, 'deadline')}',
  ];
  return 'Next week starts with ${parts.join(' and ')}.';
}
