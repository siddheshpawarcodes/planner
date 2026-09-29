import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/settings.dart';

enum AppTab { today, plan, progress, settings }

enum PlanSeg { today, tomorrow, week, upcoming }

/// Day switch transition phase (prototype `dayPhase`).
enum DayPhase { outLeft, outRight, preLeft, preRight, inPlace }

class TodayUi {
  const TodayUi({
    this.dayOffset = 0,
    this.view = TodayView.strip,
    this.phase = DayPhase.inPlace,
    this.capOpen = false,
    this.dialSel,
    this.dialIn = true,
  });

  /// 0 = Today, 1 = Tomorrow.
  final int dayOffset;
  final TodayView view;
  final DayPhase phase;
  final bool capOpen;
  final String? dialSel;
  final bool dialIn;

  TodayUi copyWith({
    int? dayOffset,
    TodayView? view,
    DayPhase? phase,
    bool? capOpen,
    Object? dialSel = _unset,
    bool? dialIn,
  }) =>
      TodayUi(
        dayOffset: dayOffset ?? this.dayOffset,
        view: view ?? this.view,
        phase: phase ?? this.phase,
        capOpen: capOpen ?? this.capOpen,
        dialSel: identical(dialSel, _unset) ? this.dialSel : dialSel as String?,
        dialIn: dialIn ?? this.dialIn,
      );
}

const Object _unset = Object();

class TodayUiController extends Notifier<TodayUi> {
  @override
  TodayUi build() => const TodayUi();
  void set(TodayUi Function(TodayUi s) f) => state = f(state);
}

final todayUiProvider =
    NotifierProvider<TodayUiController, TodayUi>(TodayUiController.new);

class PlanUi {
  const PlanUi({this.seg = PlanSeg.week, this.weekSel});
  final PlanSeg seg;

  /// Selected epoch day; null = today.
  final int? weekSel;
  PlanUi copyWith({PlanSeg? seg, int? weekSel}) =>
      PlanUi(seg: seg ?? this.seg, weekSel: weekSel ?? this.weekSel);
}

class PlanUiController extends Notifier<PlanUi> {
  @override
  PlanUi build() => const PlanUi();
  void set(PlanUi Function(PlanUi s) f) => state = f(state);
}

final planUiProvider = NotifierProvider<PlanUiController, PlanUi>(PlanUiController.new);

/// The visible shell tab, kept in sync by the router shell.
class CurrentTabController extends Notifier<AppTab> {
  @override
  AppTab build() => AppTab.today;
  void set(AppTab t) => state = t;
}

final currentTabProvider = NotifierProvider<CurrentTabController, AppTab>(CurrentTabController.new);

enum SheetKind { detail, decision, create }

/// Prefill for the TaskSheet (create or edit).
class TaskDraft {
  const TaskDraft({
    this.title = '',
    this.duration,
    this.date,
    this.editId,
    this.heard,
    this.start,
  });
  final String title;
  final int? duration;
  final int? date;
  final String? editId;

  /// "From your voice: …"
  final String? heard;

  /// Exact start when editing.
  final int? start;
}

class SheetState {
  const SheetState(this.kind, {this.taskId, this.reschedule = false, this.draft});
  final SheetKind kind;
  final String? taskId;

  /// DecisionSheet opened from Detail's Reschedule ("When should this happen?").
  final bool reschedule;
  final TaskDraft? draft;
}

class SheetController extends Notifier<SheetState?> {
  @override
  SheetState? build() => null;
  void open(SheetState s) => state = s;
  void close() => state = null;
}

final sheetProvider = NotifierProvider<SheetController, SheetState?>(SheetController.new);

/// The Motion value the platform reports; the root widget keeps it current.
class PlatformMotion extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool v) {
    if (v != state) state = v;
  }
}

final platformReducedMotionProvider =
    NotifierProvider<PlatformMotion, bool>(PlatformMotion.new);

/// Connectivity (offline shows the LOCAL chip, never a banner).
class OnlineController extends Notifier<bool> {
  @override
  bool build() => true;
  void set(bool v) => state = v;
}

final onlineProvider = NotifierProvider<OnlineController, bool>(OnlineController.new);
