import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/state/clock.dart';
import '../../app/state/derived.dart';
import '../../app/state/staging.dart';
import '../../domain/base_day.dart';
import '../../domain/capacity.dart';
import '../../domain/layout.dart';
import '../../domain/routine.dart';
import '../../domain/scheduler.dart';
import '../../domain/task.dart';
import '../../domain/time.dart';

/// Everything the Today screen shows, derived from committed state plus the
/// UI staging maps (prototype `renderVals`, Today section).
class TodayModel {
  TodayModel({
    required this.day,
    required this.isToday,
    required this.now,
    required this.routine,
    required this.layout,
    required this.dayTasks,
    required this.cur,
    required this.next,
    required this.cap,
    required this.staging,
    required this.historyDays,
  });

  final int day;
  final bool isToday;
  final double now;
  final Routine routine;
  final DayLayout layout;

  /// Tasks on screen (not hidden or staged).
  final List<Task> dayTasks;
  final Task? cur, next;
  final Capacity cap;
  final StagingState staging;
  final int historyDays;

  late final Map<String, TimelineItem> rowOf = {
    for (final x in layout.seq)
      if (x.taskId != null) x.taskId!: x
  };

  TimelineItem? get curFixed {
    if (!isToday || cur != null) return null;
    for (final x in layout.seq) {
      if (x.kind == ItemKind.fixed && now >= x.start && now < x.end) return x;
    }
    return null;
  }

  /// The now line: (label, title, meta).
  (String, String, String) get nowLine {
    if (isToday) {
      if (cur != null) {
        return ('Now', cur!.title, '${(cur!.end! - now).ceil().clamp(1, 1440)} min left');
      }
      final f = curFixed;
      if (f != null) {
        return (
          'Now',
          f.title,
          next != null ? 'then ${next!.title} at ${fmt(next!.start!)}' : 'until ${fmt(f.end)}'
        );
      }
      if (next != null) return ('Next', next!.title, 'at ${fmt(next!.start!)}');
      return ('Evening', 'is yours', 'sleep at ${fmt(routine.sleep)}');
    }
    final ev = stableSorted(layout.gaps.where((g) => g.start >= 1020),
        (a, b) => (b.end - b.start) - (a.end - a.start));
    final n = dayTasks.length;
    return (
      'Tomorrow',
      n > 0
          ? '$n ${n > 1 ? 'tasks' : 'task'} planned'
          : ev.isNotEmpty
              ? 'Open ${fmt(ev.first.start)} → ${fmt(ev.first.end)}'
              : 'Nothing planned',
      ''
    );
  }

  int get doneCount => dayTasks.where((t) => t.done).length;

  bool get placing => layout.tasks.any((t) => staging.isHiddenOrStaged(t.id));

  bool get showOver =>
      cap.isOver && !staging.overAck.contains(day) && !placing && !staging.winLit;

  Task? get overTask => overTaskOf(day, routine, layout.tasks);

  /// "Move Flutter": the last word of the task's title.
  String get overButton {
    final t = overTask;
    return t == null ? 'Move one' : 'Move ${t.title.split(' ').last}';
  }

  String get overText => overCapacityText(day, cap.over, historyDays: historyDays);

  List<Task> get missedList => isToday
      ? [
          for (final t in dayTasks)
            if (!t.done && t.end! <= now && !staging.missDismiss.contains(t.id)) t
        ]
      : const [];

  bool get showMissed => missedList.isNotEmpty && !showOver;

  String get missedText {
    final m = missedList;
    if (m.length > 1) return '${m.length} tasks didn’t happen.';
    return m.isEmpty ? '' : '${m.first.title} didn’t happen.';
  }

  String get protectedNames {
    final names = [
      for (final x in layout.base)
        if (x.kind == ItemKind.protected && x.end > (isToday ? now : 0)) x.title
    ];
    return names.isEmpty ? 'None left' : names.join(', ');
  }

  bool isMissedTask(Task t) => isToday && !t.done && t.end! <= now;

  /// The largest open gap still ahead (carries the empty state).
  TimelineItem? get eveningGap {
    final g = stableSorted(layout.gaps.where((g) => g.end > (isToday ? now : 0)),
        (a, b) => (b.end - b.start) - (a.end - a.start));
    return g.isEmpty ? null : g.first;
  }
}

final todayModelProvider = Provider<TodayModel>((ref) {
  final day = ref.watch(shownDayProvider);
  final today = ref.watch(todayProvider);
  final isToday = day == today;
  // The strip tracks minutes; the now indicator reads seconds on its own.
  final now = ref.watch(nowMinuteProvider).toDouble();
  final layout = ref.watch(dayLayoutProvider(day));
  final staging = ref.watch(stagingProvider);
  final dayTasks = [
    for (final t in layout.tasks)
      if (!staging.isHiddenOrStaged(t.id)) t
  ];
  Task? cur, next;
  if (isToday) {
    for (final t in dayTasks) {
      if (!t.done && now >= t.start! && now < t.end!) {
        cur = t;
        break;
      }
    }
    for (final t in dayTasks) {
      if (!t.done && t.start! >= now && t.id != cur?.id) {
        next = t;
        break;
      }
    }
  }
  return TodayModel(
    day: day,
    isToday: isToday,
    now: now,
    routine: ref.watch(routineProvider),
    layout: layout,
    dayTasks: dayTasks,
    cur: cur,
    next: next,
    cap: ref.watch(capacityProvider(day)),
    staging: staging,
    historyDays: ref.watch(historyDaysProvider),
  );
});
