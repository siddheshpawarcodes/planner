import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/state/actions.dart';
import '../../app/state/derived.dart';
import '../../app/state/note.dart';
import '../../app/state/sequencer.dart';
import '../../app/state/staging.dart';
import '../../app/state/ui_state.dart';
import '../../domain/category.dart';
import '../../domain/intents.dart';
import '../../domain/routine.dart';
import '../../domain/time.dart';
import 'planner_orb.dart';
import 'speech.dart';

class VoiceState {
  const VoiceState({
    this.phase = OrbState.idle,
    this.words = const [],
    this.parsed = false,
    this.showRes = false,
    this.resN = 0,
    this.res,
    this.keywords = const {},
    this.speaking = false,
    this.live = false,
  });

  final OrbState phase;

  /// Transcript words shown so far.
  final List<String> words;

  /// Understood: key words go to tx 500, the rest to t3.
  final bool parsed;

  /// The words lifted out and the parsed rows are showing.
  final bool showRes;

  /// Rows revealed so far (170ms stagger).
  final int resN;
  final VoiceResolution? res;
  final Set<String> keywords;

  /// Demo speech in progress (synthetic orb amplitude).
  final bool speaking;
  final bool live;

  bool get open => phase != OrbState.idle;
  bool get waiting =>
      phase == OrbState.result && res != null && res!.wait != VoiceWait.none && resN >= res!.rows.length;

  VoiceState copyWith({
    OrbState? phase,
    List<String>? words,
    bool? parsed,
    bool? showRes,
    int? resN,
    Object? res = _unset,
    Set<String>? keywords,
    bool? speaking,
    bool? live,
  }) =>
      VoiceState(
        phase: phase ?? this.phase,
        words: words ?? this.words,
        parsed: parsed ?? this.parsed,
        showRes: showRes ?? this.showRes,
        resN: resN ?? this.resN,
        res: identical(res, _unset) ? this.res : res as VoiceResolution?,
        keywords: keywords ?? this.keywords,
        speaking: speaking ?? this.speaking,
        live: live ?? this.live,
      );
}

const Object _unset = Object();

/// Mic level for the orb, kept apart so level updates don't rebuild the
/// overlay.
class OrbLevel extends Notifier<double?> {
  @override
  double? build() => null;
  void set(double? v) => state = v;
}

final orbLevelProvider = NotifierProvider<OrbLevel, double?>(OrbLevel.new);

/// Imperative orb impulses (tap wobble, success ripple, cancel shake).
final orbControllerProvider = Provider<OrbController>((ref) => OrbController());

/// `voiceControllerProvider`: idle → wake → listening → processing →
/// result → success | cancelled | denied (README 10).
class VoiceController extends Notifier<VoiceState> {
  final seq = Sequencer();
  SpeechInput? _speech;

  @override
  VoiceState build() {
    ref.onDispose(() {
      seq.clear();
      _speech?.cancel();
    });
    return const VoiceState();
  }

  PlannerActions get _act => ref.read(actionsProvider);

  /// Script multiplier (prototype: 0.35 under reduced motion).
  double get _m => ref.read(reducedMotionProvider) ? 0.35 : 1;

  SpeechInput _input() {
    final dbg = ref.read(voiceDebugProvider);
    if (kDebugMode && !dbg.live) {
      return DemoSpeech(() => demoUtterances[dbg.line], factor: _m, allowed: dbg.micAllowed);
    }
    return ref.read(deviceSpeechProvider);
  }

  /// Orb tap (prototype `tapOrb`): works anywhere in the app.
  Future<void> tapOrb() async {
    if (state.open) return veilTap();
    seq.clear();
    ref.read(orbControllerProvider).tapImpulse();
    Haptics.orb();
    ref.read(sheetProvider.notifier).close();
    final speech = _speech = _input();
    state = VoiceState(phase: OrbState.wake, live: speech.isLive);
    final access = await speech.prepare();
    final t = 900 * _m;
    if (access != MicAccess.granted) {
      seq.at(t, () => state = state.copyWith(phase: OrbState.denied));
      return;
    }
    seq.at(t, () {
      state = state.copyWith(phase: OrbState.listening, speaking: !speech.isLive);
      speech.listen(SpeechCallbacks(
        onWords: (text) {
          if (state.phase != OrbState.listening) return;
          state = state.copyWith(words: text.split(' ').where((w) => w.isNotEmpty).toList());
        },
        onLevel: (l) => ref.read(orbLevelProvider.notifier).set(l),
        onDone: _heard,
      ));
    });
  }

  void _heard(String text) {
    if (state.phase != OrbState.listening) return;
    ref.read(orbLevelProvider.notifier).set(null);
    state = state.copyWith(speaking: false, words: text.split(' ').where((w) => w.isNotEmpty).toList());
    if (text.trim().isEmpty) {
      _speech?.cancel();
      _finishCancel('Planner didn’t hear anything. Nothing was changed.');
      return;
    }
    final m = _m;
    seq.at(550 * m, () {
      final today = _act.today;
      final intent = parseUtterance(text, today: today);
      final res = resolveIntent(intent,
          tasks: _act.data.tasks,
          routine: _act.routine,
          today: today,
          now: _act.now,
          newId: _act.store.newId,
          createdAt: DateTime.now());
      state = state.copyWith(phase: OrbState.processing, parsed: true, res: res, keywords: intent.keywords);
      seq.at(1100 * m, () {
        state = state.copyWith(phase: OrbState.result, showRes: true);
        final nr = res.rows.length;
        for (var i = 1; i <= nr; i++) {
          seq.at(120 + i * 170 * m, () => state = state.copyWith(resN: i));
        }
        if (nr == 0) state = state.copyWith(resN: 0);
        if (res.wait == VoiceWait.none) seq.at(1200 * m + nr * 170 * m, succeed);
      });
    });
  }

  /// SUCCESS: the effect commits here; the choreography after it only
  /// explains what changed.
  Future<void> succeed() async {
    final res = state.res;
    if (res == null) return;
    ref.read(orbControllerProvider).successRipple();
    Haptics.success();
    final after = await _apply(res.effect);
    state = state.copyWith(phase: OrbState.success);
    seq.at(1200 * _m, () {
      state = const VoiceState();
      _speech?.stop();
      after?.call();
    });
  }

  /// Commits [e] and returns what to do once the orb has docked.
  Future<void Function()?> _apply(VoiceEffect e) async {
    final act = _act;
    final st = ref.read(stagingProvider.notifier);
    final m = ref.read(motionFactorProvider);
    switch (e) {
      case NoEffect():
      case AskEffect():
        return null;
      case PlaceEffect(:final tasks, :final ids, :final day, :final firstTitle, :final firstStart):
        final rel = day - act.today;
        final onToday = rel == 0 || rel == 1;
        if (onToday) {
          st.setPlace(ids, PlaceStage.hidden);
          st.update((s) => s.copyWith(winIds: ids, winLit: true));
        }
        if (!await act.store.commitTaskList(tasks)) {
          st.setPlace(ids, null);
          st.update((s) => s.copyWith(winIds: const [], winLit: false));
          act.note.say('Not saved. Nothing was changed.');
          return null;
        }
        return () {
          if (onToday) {
            act.goTab(AppTab.today);
            if (ref.read(todayUiProvider).dayOffset != rel) act.setDay(rel);
            act.seq.at(650 * m, () => act.runPlacement(ids));
          } else {
            ref.read(planUiProvider.notifier).set((p) => PlanUi(seg: PlanSeg.week, weekSel: day));
            act.goTab(AppTab.plan);
            act.flash(ids);
            act.note.say('$firstTitle added to ${when(day, firstStart)}.');
          }
        };
      case MoveEffect(:final task, :final toDay, :final slot):
        st.setHold({task.id: TaskPos(task.day, task.start, task.end)});
        ref.read(planUiProvider.notifier).set((p) => PlanUi(seg: PlanSeg.week, weekSel: task.day));
        act.goTab(AppTab.plan);
        final ok = await act.store.putTasks([
          task.copyWith(day: toDay, start: slot.start, end: slot.end, movedCount: task.movedCount + 1)
        ]);
        if (!ok) {
          st.setHold(const {}, remove: [task.id]);
          return null;
        }
        return () => act.seq.at(450 * m, () {
              st.setHold(const {}, remove: [task.id]);
              ref.read(planUiProvider.notifier).set((p) => p.copyWith(weekSel: toDay));
              st.recalc([task.day!, toDay]);
              act.seq.at(800, st.clearRecalc);
              act.flash([task.id]);
              act.note.undoable(
                  '${task.title} moved to ${dayShortNames[weekday0(toDay)]} ${fmt(slot.start)}.', () {
                final cur = act.data.task(task.id);
                if (cur != null) {
                  act.store.putTasks([
                    cur.copyWith(day: task.day, start: task.start, end: task.end, movedCount: task.movedCount)
                  ]);
                }
              });
            });
      case CompleteEffect(:final taskId):
        act.goTab(AppTab.today);
        if (ref.read(todayUiProvider).dayOffset != 0) act.setDay(0);
        await act.toggle(taskId, delayMs: 1300);
        return null;
      case DeleteEffect(:final task):
        if (!await act.store.putTasks([task.copyWith(deleted: true)])) return null;
        return () => act.note.undoable('${task.title} deleted.', () {
              final cur = act.data.task(task.id);
              if (cur != null) act.store.putTasks([cur.copyWith(deleted: false)]);
            });
      case RescheduleEffect(:final tasks, :final ids):
        st.setHold({
          for (final id in ids)
            if (act.data.task(id) case final t?) id: TaskPos(t.day, t.start, t.end)
        });
        if (!await act.store.commitTaskList(tasks)) {
          st.setHold(const {}, remove: ids);
          return null;
        }
        return () {
          act.goTab(AppTab.today);
          if (ref.read(todayUiProvider).dayOffset != 0) act.setDay(0);
          act.seq.at(300, () {
            for (final id in ids) {
              act.leave(id);
            }
            st.setHold(const {}, remove: ids);
            act.note.say('${ids.length} ${ids.length > 1 ? 'tasks' : 'task'} moved forward.');
          });
        };
      case SeriesEffect(:final series, :final occurrences):
        if (!await act.store.putSeries(series)) return null;
        await act.store.putTasks(occurrences);
        final d = dateOf(series.from);
        return () {
          ref.read(planUiProvider.notifier).set((p) => p.copyWith(seg: PlanSeg.upcoming));
          act.goTab(AppTab.plan);
          final rule = series.rule.kind == DayRuleKind.weekday
              ? 'every ${dayLongNames[series.rule.weekday]}'
              : series.rule.label.toLowerCase();
          act.note.say('${series.title} repeats $rule from ${d.day} ${monthLongNames[d.month - 1]}.');
        };
    }
  }

  /// Tap on the veil (prototype `veilTap`).
  void veilTap() {
    final p = state.phase;
    final res = state.res;
    if (p == OrbState.wake || p == OrbState.listening || p == OrbState.processing) return cancel();
    if (p == OrbState.result && res != null && res.wait != VoiceWait.none) {
      return res.wait == VoiceWait.confirm ? no() : close();
    }
    if (p == OrbState.result) return cancel();
    if (p == OrbState.denied) return close();
  }

  /// Cancelled: a small "no" shake; nothing was changed.
  void cancel() {
    seq.clear();
    _speech?.cancel();
    _finishCancel('Cancelled. Nothing was changed.');
  }

  void _finishCancel(String text) {
    ref.read(orbLevelProvider.notifier).set(null);
    ref.read(orbControllerProvider).cancelShake();
    state = state.copyWith(phase: OrbState.cancelled, speaking: false);
    seq.at(700 * ref.read(motionFactorProvider) + 30, () {
      state = const VoiceState();
      ref.read(noteProvider.notifier).say(text);
    });
  }

  void close() {
    seq.clear();
    _speech?.cancel();
    ref.read(orbLevelProvider.notifier).set(null);
    state = const VoiceState();
  }

  /// Confirm, or the answer's primary action.
  void yes() {
    final res = state.res;
    if (res == null) return;
    if (res.wait == VoiceWait.confirm) {
      succeed();
      return;
    }
    if (res.effect case AskEffect(:final day)) {
      close();
      final rel = day - _act.today;
      if (rel == 0 || rel == 1) {
        _act.goTab(AppTab.today);
        _act.setDay(rel);
      } else {
        ref.read(planUiProvider.notifier).set((p) => PlanUi(seg: PlanSeg.week, weekSel: day));
        _act.goTab(AppTab.plan);
      }
      return;
    }
    close();
  }

  void no() {
    final res = state.res;
    close();
    if (res != null && res.wait == VoiceWait.confirm) {
      ref.read(noteProvider.notifier).say('Kept. Nothing was changed.');
    }
  }

  /// Microphone denied › Allow microphone.
  Future<void> allowMic() async {
    final speech = _speech ?? _input();
    if (speech is DemoSpeech) {
      ref.read(voiceDebugProvider.notifier).set((v) => v.copyWith(micAllowed: true));
    }
    final a = await speech.requestAccess();
    close();
    if (a == MicAccess.granted) seq.at(250, tapOrb);
  }

  /// Microphone denied › Type instead: opens the TaskSheet.
  void typeInstead() {
    close();
    seq.at(100, () => _act.openCreate());
  }

  /// Core colour while the voice result shows.
  Category? get core => state.res?.core;
}

final voiceControllerProvider =
    NotifierProvider<VoiceController, VoiceState>(VoiceController.new);
