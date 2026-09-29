import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Placement staging (prototype `place`): hidden → staged → placed.
enum PlaceStage { hidden, staged, placed }

/// Completion sweep (prototype `sweeping`): pre (delayed), a (sweeping),
/// b (settling).
enum SweepPhase { pre, a, b }

enum LeavePhase { lift, fly }

class TaskPos {
  const TaskPos(this.day, this.start, this.end);
  final int? day;
  final int? start, end;
}

class LeavingInfo {
  const LeavingInfo(this.y, this.h, this.phase);
  final double y, h;
  final LeavePhase phase;
}

/// UI-only staging maps. Visual state that explains a change which has
/// already been committed; nothing here gates data.
class StagingState {
  const StagingState({
    this.place = const {},
    this.hold = const {},
    this.leaving = const {},
    this.sweeping = const {},
    this.fresh = const {},
    this.scanning = false,
    this.winLit = false,
    this.winIds = const [],
    this.navBump = 0,
    this.recalcDays = const [],
    this.recalcKey = 0,
    this.overAck = const {},
    this.overAckWeek = const {},
    this.missDismiss = const {},
  });

  final Map<String, PlaceStage> place;
  final Map<String, TaskPos> hold;
  final Map<String, LeavingInfo> leaving;
  final Map<String, SweepPhase> sweeping;

  /// Recently moved or added ids (ring highlight), with a timestamp.
  final Map<String, int> fresh;
  final bool scanning, winLit;
  final List<String> winIds;

  /// Timestamp of the last "incoming move" bump on Plan / Tomorrow.
  final int navBump;

  /// Plan board columns to scan after a move.
  final List<int> recalcDays;
  final int recalcKey;

  /// Days whose over-capacity row was answered with Keep anyway.
  final Set<int> overAck, overAckWeek;
  final Set<String> missDismiss;

  bool isHiddenOrStaged(String id) {
    final p = place[id];
    return p == PlaceStage.hidden || p == PlaceStage.staged;
  }

  StagingState copyWith({
    Map<String, PlaceStage>? place,
    Map<String, TaskPos>? hold,
    Map<String, LeavingInfo>? leaving,
    Map<String, SweepPhase>? sweeping,
    Map<String, int>? fresh,
    bool? scanning,
    bool? winLit,
    List<String>? winIds,
    int? navBump,
    List<int>? recalcDays,
    int? recalcKey,
    Set<int>? overAck,
    Set<int>? overAckWeek,
    Set<String>? missDismiss,
  }) =>
      StagingState(
        place: place ?? this.place,
        hold: hold ?? this.hold,
        leaving: leaving ?? this.leaving,
        sweeping: sweeping ?? this.sweeping,
        fresh: fresh ?? this.fresh,
        scanning: scanning ?? this.scanning,
        winLit: winLit ?? this.winLit,
        winIds: winIds ?? this.winIds,
        navBump: navBump ?? this.navBump,
        recalcDays: recalcDays ?? this.recalcDays,
        recalcKey: recalcKey ?? this.recalcKey,
        overAck: overAck ?? this.overAck,
        overAckWeek: overAckWeek ?? this.overAckWeek,
        missDismiss: missDismiss ?? this.missDismiss,
      );
}

class StagingController extends Notifier<StagingState> {
  /// Last laid-out geometry of each Today block (prototype `lastTop`), used
  /// to fly a block out after it has already moved in the data.
  final lastTop = <String, (double, double)>{};

  @override
  StagingState build() => const StagingState();

  void update(StagingState Function(StagingState s) f) => state = f(state);

  void setPlace(Iterable<String> ids, PlaceStage? stage) {
    final m = Map.of(state.place);
    for (final id in ids) {
      if (stage == null) {
        m.remove(id);
      } else {
        m[id] = stage;
      }
    }
    state = state.copyWith(place: m);
  }

  void setSweep(String id, SweepPhase? p) {
    final m = Map.of(state.sweeping);
    p == null ? m.remove(id) : m[id] = p;
    state = state.copyWith(sweeping: m);
  }

  void setLeaving(String id, LeavingInfo? l) {
    final m = Map.of(state.leaving);
    l == null ? m.remove(id) : m[id] = l;
    state = state.copyWith(leaving: m);
  }

  void setHold(Map<String, TaskPos> add, {Iterable<String> remove = const []}) {
    final m = Map.of(state.hold)..addAll(add);
    for (final id in remove) {
      m.remove(id);
    }
    state = state.copyWith(hold: m);
  }

  void setFresh(Iterable<String> ids, bool on) {
    final m = Map.of(state.fresh);
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final id in ids) {
      on ? m[id] = now : m.remove(id);
    }
    state = state.copyWith(fresh: m);
  }

  void bumpNav() =>
      state = state.copyWith(navBump: DateTime.now().millisecondsSinceEpoch);

  void recalc(List<int> days) => state = state.copyWith(
      recalcDays: days, recalcKey: state.recalcKey + 1);

  void clearRecalc() => state = state.copyWith(recalcDays: const []);

  void reset() {
    lastTop.clear();
    state = const StagingState();
  }
}

final stagingProvider =
    NotifierProvider<StagingController, StagingState>(StagingController.new);
