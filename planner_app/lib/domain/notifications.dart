import 'task.dart';
import 'time.dart';

enum NoteKind { nextTask, missed, review }

/// One local notification Planner wants scheduled.
class PlannedNote {
  const PlannedNote(this.id, this.kind, this.at, this.title, this.body);
  final int id;
  final NoteKind kind;
  final DateTime at;
  final String title, body;
  @override
  String toString() => 'PlannedNote($id ${kind.name} $at "$title" "$body")';
}

/// Everything to schedule from [now] (README 6.10), recomputed whenever the
/// plan changes:
/// - **Next task**, 5 minutes before each upcoming task in the next week.
/// - **Missed tasks**, one gentle check-in per day, 15 minutes after the
///   day's last open task should have ended (never a pile-up). Completing
///   the tasks re-plans it away.
/// - **Weekly review**, Sunday 21:00.
List<PlannedNote> planNotifications({
  required List<Task> tasks,
  required DateTime now,
  bool nextTask = true,
  bool missed = true,
  bool review = true,
  int horizonDays = 7,
  int maxNext = 40,
}) {
  final today = dayOf(now);
  DateTime at(int day, int minute) => dateOf(day).add(Duration(minutes: minute));
  final live = stableSorted(
      tasks.where((t) => t.isLive && !t.done && t.day! >= today && t.day! < today + horizonDays),
      (a, b) => a.day != b.day ? a.day! - b.day! : a.start! - b.start!);
  final out = <PlannedNote>[];

  if (nextTask) {
    var n = 0;
    for (final t in live) {
      final when = at(t.day!, t.start! - 5);
      if (!when.isAfter(now)) continue;
      out.add(PlannedNote(1000 + n, NoteKind.nextTask, when, t.title,
          'Starts in 5 minutes, ${fmt(t.start!)} → ${fmt(t.end!)}.'));
      if (++n >= maxNext) break;
    }
  }

  if (missed) {
    for (var d = today; d < today + horizonDays; d++) {
      final open = live.where((t) => t.day == d).toList();
      if (open.isEmpty) continue;
      final last = open.map((t) => t.end!).reduce((a, b) => a > b ? a : b);
      final when = at(d, last + 15);
      if (!when.isAfter(now)) continue;
      out.add(PlannedNote(
        2000 + (d - today),
        NoteKind.missed,
        when,
        'Planner',
        open.length == 1
            ? '${open.first.title} is still open. Planner can find it a new time.'
            : 'Some of today’s plan is still open. Planner can find new times.',
      ));
    }
  }

  if (review) {
    var sun = today + (6 - weekday0(today));
    if (!at(sun, 1260).isAfter(now)) sun += 7;
    out.add(PlannedNote(3000, NoteKind.review, at(sun, 1260), 'Your week is ready to review.',
        'See where your time went, then plan next week.'));
  }
  return out;
}
