import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/planner_data.dart';
import '../../domain/routine.dart';
import '../../domain/capacity.dart';
import '../../domain/scheduler.dart';
import '../../domain/series.dart';
import '../../domain/task.dart';
import '../../domain/time.dart';
import '../../features/tasks/task_form.dart';
import '../router.dart';
import 'clock.dart';
import 'derived.dart';
import 'note.dart';
import 'sequencer.dart';
import 'staging.dart';
import 'store.dart';
import 'ui_state.dart';

final actionsProvider = Provider<PlannerActions>((ref) {
  final a = PlannerActions(ref);
  ref.onDispose(a.seq.clear);
  return a;
});

/// Haptics (README 10): 12ms complete, 8ms orb tap, 5ms placement, 16ms
/// voice success. Mapped onto the platform's closest feedback.
abstract final class Haptics {
  static void complete() => HapticFeedback.lightImpact();
  static void orb() => HapticFeedback.selectionClick();
  static void place() => HapticFeedback.selectionClick();
  static void success() => HapticFeedback.mediumImpact();
}

/// User actions. The rule in every method: commit through the store first,
/// then stage visuals (which only explain the change), then announce it in
/// the note strip with Undo where it makes sense.
class PlannerActions {
  PlannerActions(this.ref);
  final Ref ref;
  final seq = Sequencer();

  PlannerStore get store => ref.read(plannerStoreProvider.notifier);
  PlannerData get data => ref.read(plannerStoreProvider);
  StagingController get staging => ref.read(stagingProvider.notifier);
  NoteController get note => ref.read(noteProvider.notifier);
  Routine get routine => data.routine;

  /// Prototype `M()`: 1, or 0.05 under reduced motion.
  double get m => ref.read(motionFactorProvider);
  int get today => ref.read(todayProvider);
  /// Whole minutes: scheduling decisions happen on the minute ("finished at
  /// 21:40" ends the block at 21:40, not 21:45).
  double get now => ref.read(nowMinuteProvider).toDouble();
  int get shownDay => ref.read(shownDayProvider);
  AppTab get tab => ref.read(currentTabProvider);

  void _failed(void Function() retry) =>
      note.say('Not saved, tap to retry', actionLabel: 'Retry', action: retry);

  // ---------------------------------------------------------------- tabs

  void goTab(AppTab t) => ref.read(routerProvider).go(tabPath(t));

  /// Settings › Edit routine: re-runs onboarding prefilled.
  void editRoutine() => ref.read(routerProvider).push('$onboardingPath?edit=1');

  /// Today / Tomorrow switch (prototype `setDay`): out 170, then in.
  void setDay(int off) {
    final ui = ref.read(todayUiProvider);
    if (off == ui.dayOffset) return;
    final ctl = ref.read(todayUiProvider.notifier);
    final fwd = off > ui.dayOffset;
    ctl.set((s) => s.copyWith(phase: fwd ? DayPhase.outLeft : DayPhase.outRight, dialSel: null));
    seq.at(170 * m, () {
      ctl.set((s) => s.copyWith(dayOffset: off, phase: fwd ? DayPhase.preRight : DayPhase.preLeft));
      seq.at(30, () => ctl.set((s) => s.copyWith(phase: DayPhase.inPlace)));
    });
  }

  // ---------------------------------------------------------- completion

  /// Completion (prototype `toggle`). The task is done in the data at once;
  /// `sweeping` only stages the visual. Finished during its block, the end
  /// moves to now and the note says how much time came back.
  Future<void> toggle(String id, {bool fromSwipe = false, int delayMs = 0}) async {
    final t = data.task(id);
    if (t == null) return;
    if (t.done) {
      if (fromSwipe) return;
      if (!await store.putTasks([uncompleteTask(t)])) _failed(() => toggle(id));
      return;
    }
    final d0 = delayMs * m;
    Haptics.complete();
    final (nt, early) = completeTask(t, today: today, now: now);
    staging.setSweep(id, SweepPhase.pre); // visual only; keeps the block undone-looking
    if (!await store.putTasks([nt])) {
      staging.setSweep(id, null);
      _failed(() => toggle(id, fromSwipe: fromSwipe, delayMs: delayMs));
      return;
    }
    if (d0 > 0) {
      seq.at(d0, () => staging.setSweep(id, SweepPhase.a));
    } else {
      staging.setSweep(id, SweepPhase.a);
    }
    seq.at(d0 + 380 * m, () => staging.setSweep(id, SweepPhase.b));
    seq.at(d0 + 1000 * m, () => staging.setSweep(id, null));
    note.undoable(
      early > 0
          ? '${t.title} done early. $early min back in your evening.'
          : '${t.title} done.',
      () {
        final cur = data.task(id);
        if (cur != null && cur.done) store.putTasks([uncompleteTask(cur)]);
      },
    );
  }

  // --------------------------------------------------------------- moves

  /// Flies a Today block out from its last drawn spot (prototype `leave`).
  void leave(String id) {
    final c = staging.lastTop[id];
    if (c == null) return;
    staging.setLeaving(id, LeavingInfo(c.$1, c.$2, LeavePhase.lift));
    seq.at(60, () => staging.setLeaving(id, LeavingInfo(c.$1, c.$2, LeavePhase.fly)));
    seq.at(1000 * m + 80, () => staging.setLeaving(id, null));
  }

  void flash(List<String> ids, {int ms = 1600}) {
    staging.setFresh(ids, true);
    seq.at(ms, () => staging.setFresh(ids, false));
  }

  /// Moves a task (prototype `moveTask`), counting it as a reschedule.
  Future<void> moveTask(String id, int day, int start, int end, {String? why}) async {
    final t = data.task(id);
    if (t == null) return;
    final onToday = tab == AppTab.today && t.day == shownDay && day != t.day;
    if (onToday) leave(id);
    final ok = await store.putTasks(
        [t.copyWith(day: day, start: start, end: end, movedCount: t.movedCount + 1)]);
    if (!ok) {
      _failed(() => moveTask(id, day, start, end, why: why));
      return;
    }
    flash([id], ms: 1400);
    if (day != shownDay) staging.bumpNav();
    note.undoable(why ?? '${t.title} moved to ${when(day, start)}.', () {
      final cur = data.task(id);
      if (cur != null) {
        store.putTasks([
          cur.copyWith(day: t.day, start: t.start, end: t.end, movedCount: t.movedCount)
        ]);
      }
    });
  }

  /// Today's over-capacity "Move `<task>`" (prototype `moveOver`).
  Future<void> moveOver(int day) async {
    final s = moveOverToday(day, routine, data.tasks);
    if (s == null) {
      note.say('No lighter evening this week. Keeping it.');
      return;
    }
    Haptics.orb();
    await moveTask(s.task.id, s.day, s.slot.start, s.slot.end,
        why: '${s.task.title} moved to ${when(s.day, s.slot.start)}. Your evening fits again.');
  }

  void keepOver(int day) {
    staging.update((s) => s.copyWith(overAck: {...s.overAck, day}));
    note.say('Kept. The last block runs into your wind-down.');
  }

  void missedLater(Iterable<String> ids) =>
      staging.update((s) => s.copyWith(missDismiss: {...s.missDismiss, ...ids}));

  // -------------------------------------------------------------- sheets

  bool isMissedTask(Task t) => isMissed(t, today, now);

  /// Tap on a block: Detail, or the Decision sheet when missed.
  void openBlock(String id) {
    final t = data.task(id);
    if (t == null) return;
    ref.read(sheetProvider.notifier).open(isMissedTask(t)
        ? SheetState(SheetKind.decision, taskId: id)
        : SheetState(SheetKind.detail, taskId: id));
  }

  void openDecision(String id, {bool reschedule = false}) => ref
      .read(sheetProvider.notifier)
      .open(SheetState(SheetKind.decision, taskId: id, reschedule: reschedule));

  void openCreate({int? date, TaskDraft? draft}) => ref.read(sheetProvider.notifier).open(
      SheetState(SheetKind.create, draft: draft ?? TaskDraft(date: date)));

  void closeSheet() => ref.read(sheetProvider.notifier).close();

  void offlineInfo() =>
      note.say('Offline. Everything is saved on this phone and backs up when you reconnect.');

  // ------------------------------------------------------- task sheet

  void openEdit(String id) {
    final t = data.task(id);
    if (t == null || !t.isScheduled) return;
    ref.read(sheetProvider.notifier).open(
        SheetState(SheetKind.create, draft: TaskDraft(editId: id, title: t.title)));
  }

  /// TaskSheet › Schedule (prototype `schedule`). Commits first; then the
  /// placement sequence explains it on Today (today or tomorrow), or the
  /// Week board flashes the new block for later days.
  Future<void> schedule(TaskForm f) async {
    final sl = f.slot(routine, data.tasks, today: today, now: now);
    if (sl == null) return;
    final cat = f.effectiveCat;
    if (f.editId != null) {
      final t = data.task(f.editId!);
      if (t == null) return;
      final ok = await store.putTasks([
        t.copyWith(
          title: f.title.trim(),
          cat: cat,
          day: sl.day,
          start: sl.start,
          end: sl.end,
          duration: f.duration,
          priority: f.priority,
          deadline: f.deadline,
          recurrence: f.recur,
        )
      ]);
      if (!ok) return _failed(() => schedule(f));
      closeSheet();
      note.say('Saved.');
      return;
    }
    final id = store.newId();
    var t = Task.make(id, f.title.trim(), cat, sl.day, sl.start, f.duration!,
        priority: f.priority,
        deadline: f.deadline,
        recurrence: f.recur,
        source: f.heard != null ? Source.voice : Source.manual,
        createdAt: DateTime.now());
    final extra = <Task>[];
    Series? series;
    if (f.recur != null) {
      series = Series(
          id: 's$id',
          title: t.title,
          cat: cat,
          rule: f.recur!,
          start: sl.start,
          end: sl.end,
          from: sl.day);
      t = t.copyWith(seriesId: series.id);
      extra.addAll(materializeSeries(series, [...data.tasks, t], routine,
          fromDay: sl.day + 1, toDay: today + kSeriesHorizonDays));
    }
    closeSheet();
    final rel = sl.day - today;
    final onToday = rel == 0 || rel == 1;
    if (onToday) {
      // Staging first (UI only), so the new block never flashes in place.
      staging.setPlace([id], PlaceStage.hidden);
      staging.update((s) => s.copyWith(winIds: [id], winLit: true));
    }
    final ok = await store.putTasks([t, ...extra]);
    if (series != null && ok) await store.putSeries(series);
    if (!ok) {
      staging.setPlace([id], null);
      staging.update((s) => s.copyWith(winIds: const [], winLit: false));
      return _failed(() => schedule(f));
    }
    if (onToday) {
      goTab(AppTab.today);
      if (ref.read(todayUiProvider).dayOffset != rel) setDay(rel);
      seq.at(560 * m, () => runPlacement([id]));
    } else {
      ref.read(planUiProvider.notifier).set((p) => p.copyWith(seg: PlanSeg.week, weekSel: sl.day));
      goTab(AppTab.plan);
      flash([id]);
      note.say('${t.title} added to ${when(sl.day, sl.start)}.');
    }
  }

  /// The placement sequence (prototype `runPlacement`): the window lights
  /// and a scan line sweeps it; each task is introduced at the top of the
  /// window, then 360ms later placed at its exact minute, 620ms apart.
  /// Capacity and the odometer update as each one lands.
  void runPlacement(List<String> ids) {
    final mm = ref.read(reducedMotionProvider) ? 0.1 : 1.0;
    staging.update((s) => s.copyWith(scanning: true, winLit: true, winIds: ids));
    final t = 850 * mm;
    seq.at(t, () => staging.update((s) => s.copyWith(scanning: false)));
    for (final (i, id) in ids.indexed) {
      final t0 = t + i * 620 * mm;
      seq.at(t0, () => staging.setPlace([id], PlaceStage.staged));
      seq.at(t0 + 360 * mm, () {
        Haptics.place();
        staging.setPlace([id], PlaceStage.placed);
      });
    }
    seq.at(t + ids.length * 620 * mm + 500 * mm, () {
      staging.update((s) => s.copyWith(winLit: false, winIds: const []));
      staging.setPlace(ids, null);
      final placed = [for (final id in ids) data.task(id)].whereType<Task>().toList();
      if (placed.length == 1) {
        final p = placed.first;
        note.say('${p.title} placed at ${p.day == today ? 'today' : 'tomorrow'}, ${fmt(p.start!)}.');
      } else if (placed.isNotEmpty) {
        note.say('${placed.length} tasks placed ${placed.first.day == today ? 'tonight' : 'tomorrow evening'}.');
      }
    });
  }

  // ------------------------------------------------------ detail sheet

  Future<void> completeFromSheet(String id) async {
    final t = data.task(id);
    closeSheet();
    if (t == null) return;
    if (t.done) {
      await store.putTasks([uncompleteTask(t)]);
      return;
    }
    await toggle(id, delayMs: 300);
  }

  Future<void> skipTask(String id) async {
    final t = data.task(id);
    if (t == null) return;
    if (!await store.putTasks([t.copyWith(skipped: true)])) return _failed(() => skipTask(id));
    closeSheet();
    note.undoable('${t.title} skipped this time.', () {
      final cur = data.task(id);
      if (cur != null) store.putTasks([cur.copyWith(skipped: false)]);
    });
  }

  Future<void> deleteTask(String id) async {
    final t = data.task(id);
    if (t == null) return;
    if (!await store.putTasks([t.copyWith(deleted: true)])) return _failed(() => deleteTask(id));
    closeSheet();
    note.undoable('${t.title} deleted.', () {
      final cur = data.task(id);
      if (cur != null) store.putTasks([cur.copyWith(deleted: false)]);
    });
  }

  /// Keeps every series materialised [kSeriesHorizonDays] ahead.
  Future<void> topUpSeries() async {
    var all = data.tasks;
    final add = <Task>[];
    for (final s in data.series) {
      final occ = materializeSeries(s, all, routine, fromDay: today, toDay: today + kSeriesHorizonDays);
      add.addAll(occ);
      all = [...all, ...occ];
    }
    if (add.isNotEmpty) await store.putTasks(add);
  }

  // --------------------------------------------------------- onboarding

  /// "Build my rhythm": the routine commits here, before the assembly
  /// explains it. Editing an existing routine also refits the week's undone
  /// tasks around it. Returns false when the write failed.
  Future<bool> applyRoutine(Routine r) async {
    if (!await store.setRoutine(r)) return false;
    final next = reflowForRoutine(data.tasks, r, today, now);
    if (!identical(next, data.tasks) && !await store.commitTaskList(next)) return false;
    if (!data.onboarded) return store.setMeta(onboarded: true);
    return true;
  }

  // --------------------------------------------------------------- plan

  /// The selected board day (Today and Tomorrow modes pin it).
  int get planSel {
    final p = ref.read(planUiProvider);
    return switch (p.seg) {
      PlanSeg.today => today,
      PlanSeg.tomorrow => today + 1,
      _ => p.weekSel ?? today,
    };
  }

  void setSeg(PlanSeg seg) => ref.read(planUiProvider.notifier).set((p) => switch (seg) {
        PlanSeg.today => PlanUi(seg: seg, weekSel: today),
        PlanSeg.tomorrow => PlanUi(seg: seg, weekSel: today + 1),
        _ => p.copyWith(seg: seg),
      });

  /// Tapping a column (prototype `selDay`): in the day zooms, today and
  /// tomorrow keep their zoom; any other day opens Week on it.
  void selDay(int d) {
    final p = ref.read(planUiProvider);
    final ctl = ref.read(planUiProvider.notifier);
    if (p.seg != PlanSeg.week) {
      if (d == today) return ctl.set((_) => PlanUi(seg: PlanSeg.today, weekSel: d));
      if (d == today + 1) return ctl.set((_) => PlanUi(seg: PlanSeg.tomorrow, weekSel: d));
      return ctl.set((_) => PlanUi(seg: PlanSeg.week, weekSel: d));
    }
    ctl.set((x) => x.copyWith(weekSel: d));
  }

  void _scan(List<int> days) {
    staging.recalc(days);
    seq.at(900, staging.clearRecalc);
  }

  /// Drop after a drag (prototype `wUp`): ripple, commit, scan both days,
  /// and say what happened. A move to another day counts as a reschedule.
  Future<void> dropOnBoard(String id, int day, int start) async {
    final before = data.tasks;
    final t = data.task(id);
    if (t == null || t.done) return;
    final from = t.day!;
    var next = ripple(before, id, day, start, routine);
    final moved = next.firstWhere((x) => x.id == id);
    if (moved.day == t.day && moved.start == t.start) return;
    if (moved.day != from) {
      next = [
        for (final x in next) x.id == id ? x.copyWith(movedCount: t.movedCount + 1) : x
      ];
    }
    final pushed = ripplePushed(before, next, id);
    final byId = {for (final x in before) x.id: x};
    final changed = [for (final x in next) if (!identical(byId[x.id], x)) x];
    if (!await store.commitTaskList(next)) return _failed(() => dropOnBoard(id, day, start));
    Haptics.place();
    _scan([from, day]);
    final c = capOf(moved.day!, routine, next, moved.day == today ? now : 0);
    final dn = dayLongNames[weekday0(moved.day!)];
    final tail = c.isOver ? ' $dn is now ${dur(c.over)} over what fits.' : ' $dn: ${dur(c.planned)} planned.';
    final made = pushed > 0 ? ' $pushed ${pushed > 1 ? 'blocks' : 'block'} made room.' : '';
    note.undoable('${t.title} moved to ${when(moved.day!, moved.start!)}.$made$tail', () {
      store.putTasks([for (final x in changed) byId[x.id]!]);
    });
  }

  /// "Move one" under the board (prototype `moveOverGeneric`).
  Future<void> moveOneFrom(int d) async {
    final m = moveOneBlock(d, routine, data.tasks,
        today: today, now: now, lastDay: weekStart(d) + 6);
    if (m == null) {
      note.say('No lighter day this week. Keeping it.');
      return;
    }
    await moveTask(m.task.id, m.day, m.slot.start, m.slot.end,
        why: '${m.task.title} moved to ${when(m.day, m.slot.start)}. ${dayLongNames[weekday0(d)]} fits again.');
    _scan([d, m.day]);
  }

  void keepWeek(int d) =>
      staging.update((s) => s.copyWith(overAckWeek: {...s.overAckWeek, d}));

  /// "Fit in" for an Unscheduled task (prototype `fitIn`).
  Future<void> fitIn(String id) async {
    final t = data.task(id);
    if (t == null) return;
    final sl = fitInSlot(t, routine, data.tasks, today: today, now: now);
    if (sl == null) {
      note.say('No room for ${t.title} this week.');
      return;
    }
    if (!await store.putTasks([t.copyWith(day: sl.day, start: sl.start, end: sl.end)])) {
      return _failed(() => fitIn(id));
    }
    flash([id]);
    final p = ref.read(planUiProvider);
    if (p.seg != PlanSeg.upcoming && p.seg == PlanSeg.week) {
      ref.read(planUiProvider.notifier).set((x) => x.copyWith(weekSel: sl.day));
    }
    note.undoable(
        '${t.title} fits ${sl.day == today ? 'today, ${fmt(sl.start)}' : when(sl.day, sl.start)}.', () {
      final cur = data.task(id);
      if (cur != null) store.putTasks([cur.copyWith(day: null, start: null, end: null)]);
    });
  }

  // ------------------------------------------------------ missed flow

  /// DecisionSheet choice (prototype `reschedTo`). The move commits first;
  /// the sheet closes, the block is held at its old spot for 260ms, then
  /// lifts and flies toward its destination while the rows below reflow.
  Future<void> reschedTo(String id, int day, Slot sl) async {
    final t = data.task(id);
    if (t == null) return;
    final same = day == t.day;
    final onView = tab == AppTab.today && t.day == shownDay;
    if (onView && !same) {
      staging.setHold({id: TaskPos(t.day, t.start, t.end)});
    }
    final ok = await store.putTasks(
        [t.copyWith(day: day, start: sl.start, end: sl.end, movedCount: t.movedCount + 1)]);
    if (!ok) {
      staging.setHold(const {}, remove: [id]);
      return _failed(() => reschedTo(id, day, sl));
    }
    closeSheet();
    seq.at(260 * m, () {
      if (onView && !same) {
        leave(id);
        staging.setHold(const {}, remove: [id]);
        staging.bumpNav();
      }
      if (tab == AppTab.plan) flash([id]);
    });
    note.undoable(
        '${t.title} moved to ${day == today ? 'today, ${fmt(sl.start)}' : when(day, sl.start)}.', () {
      final cur = data.task(id);
      if (cur != null) {
        store.putTasks([cur.copyWith(day: t.day, start: t.start, end: t.end, movedCount: t.movedCount)]);
      }
    });
  }
}
