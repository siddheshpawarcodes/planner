import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router.dart';
import '../../app/state/actions.dart';
import '../../app/state/derived.dart';
import '../../app/state/store.dart';
import '../../app/state/ui_state.dart';
import '../../app/theme/planner_theme.dart';
import '../voice/wake_word.dart';
import 'alarm_engine.dart';
import 'alarm_platform.dart';
import 'alarm_screen.dart';

/// The alarms ringing right now (the first one is on screen).
final ringingAlarmsProvider = NotifierProvider<RingingAlarms, List<PlannedAlarm>>(RingingAlarms.new);

class RingingAlarms extends Notifier<List<PlannedAlarm>> {
  @override
  List<PlannedAlarm> build() => const [];
  void set(List<PlannedAlarm> v) => state = v;
}

/// Answers to a ringing alarm. Each stops the sound first, then acts.
class AlarmAnswers {
  AlarmAnswers(this.ref);
  final Ref ref;

  AlarmEngine get _engine => ref.read(alarmEngineProvider);
  AlarmPlatform get _platform => ref.read(alarmPlatformProvider);

  /// Done: completes the task (as the check on Today does).
  Future<void> done(PlannedAlarm a) async {
    await _engine.stop(a.id);
    final t = a.taskId == null ? null : ref.read(plannerStoreProvider).task(a.taskId!);
    if (t != null && !t.done) await ref.read(actionsProvider).toggle(t.id);
    await _platform.release();
  }

  Future<void> snooze(PlannedAlarm a) async {
    final m = ref.read(settingsProvider).alarm.snoozeMinutes;
    await _engine.snooze(a.id, Duration(minutes: m));
    await _platform.release();
  }

  /// Start now: unlock and open the task on Today. Unlocking comes first,
  /// so stopping the alarm doesn't send Planner back behind the lock screen.
  Future<void> start(PlannedAlarm a) async {
    final unlocked = await _platform.unlockAndStay();
    await _engine.stop(a.id);
    if (!unlocked) return;
    final act = ref.read(actionsProvider);
    act.goTab(AppTab.today);
    final t = a.taskId == null ? null : ref.read(plannerStoreProvider).task(a.taskId!);
    if (t != null && t.isLive) {
      ref.read(todayUiProvider.notifier).set((u) => u.copyWith(dayOffset: 0));
      act.openBlock(t.id);
    }
  }
}

final alarmAnswersProvider = Provider<AlarmAnswers>(AlarmAnswers.new);

/// Listens for ringing alarms and puts the alarm screen over everything
/// (a root route, so system back can't reach the plan beneath, even over
/// the lock screen). When the last alarm stops, however it stopped, the
/// screen closes.
class AlarmHost extends ConsumerStatefulWidget {
  const AlarmHost({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<AlarmHost> createState() => _AlarmHostState();
}

class _AlarmHostState extends ConsumerState<AlarmHost> {
  StreamSubscription<List<PlannedAlarm>>? _sub;
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    _sub = ref.read(alarmEngineProvider).ringing.listen(_onRinging);
  }

  void _onRinging(List<PlannedAlarm> list) {
    if (!mounted) return;
    if (kDebugMode) debugPrint('[alarm] ringing ${list.map((a) => a.title).toList()}');
    ref.read(ringingAlarmsProvider.notifier).set(list);
    final router = ref.read(routerProvider);
    if (list.isNotEmpty && !_showing) {
      _showing = true;
      ref.read(shellCoveredProvider.notifier).set(true);
      ref.read(alarmPlatformProvider).showOverLock();
      router.push(alarmPath);
    } else if (list.isEmpty && _showing) {
      _showing = false;
      ref.read(shellCoveredProvider.notifier).set(false);
      if (router.canPop()) router.pop();
      ref.read(alarmPlatformProvider).release();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The `/alarm` route: the first ringing alarm in its chosen look.
class AlarmPage extends ConsumerWidget {
  const AlarmPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(ringingAlarmsProvider);
    if (list.isEmpty) return const ColoredBox(color: Colors.black);
    final a = list.first;
    final prefs = ref.watch(settingsProvider).alarm;
    final answers = ref.read(alarmAnswersProvider);
    return PopScope(
      canPop: false,
      child: AlarmScreen(
        key: ValueKey(a.id),
        alarm: a,
        look: prefs.lookFor(a.cat),
        prefs: prefs,
        reduced: PlannerMotion.reduced(context),
        onDone: () => answers.done(a),
        onSnooze: () => answers.snooze(a),
        onStart: () => answers.start(a),
      ),
    );
  }
}
