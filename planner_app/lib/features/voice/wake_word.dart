import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/state/derived.dart';
import '../../app/state/store.dart';
import '../../app/state/ui_state.dart';
import 'speech.dart';
import 'voice_controller.dart';

/// An on-device keyword spotter for "Hey Planner" (README 6.3). It runs only
/// while [wakeGateProvider] says the wake phrase is armed; there is no
/// background service.
/// The app uses Vosk on Android (`vosk_engine.dart`); another spotter can
/// replace it by implementing this interface.
abstract class WakeWordEngine {
  /// Configured and able to run (key, keyword model, platform).
  bool get available;

  /// Why not, for Settings and debug logs; null when [available].
  String? get unavailableReason;

  /// Starts listening for the phrase; [onWake] fires once per detection.
  /// [phrases] are words a request is likely to contain (the user's task
  /// names), for engines that can favour them.
  Future<void> start(VoidCallback onWake, {List<String> phrases = const []});

  /// Stops listening and releases the microphone.
  Future<void> stop();

  /// Right after a wake: the sentence the engine is still hearing, as speech
  /// input for the voice screen, or null when it has let go of the
  /// microphone (the device recogniser takes the request).
  HandOverSpeech? takeOver();
}

/// Tap-to-talk only: tests, and platforms without a spotter.
class NoWakeWordEngine implements WakeWordEngine {
  const NoWakeWordEngine([this.unavailableReason = 'No wake-word engine on this platform.']);
  @override
  bool get available => false;
  @override
  final String? unavailableReason;
  @override
  Future<void> start(VoidCallback onWake, {List<String> phrases = const []}) async {}
  @override
  Future<void> stop() async {}
  @override
  HandOverSpeech? takeOver() => null;
}

final wakeWordEngineProvider = Provider<WakeWordEngine>((ref) => const NoWakeWordEngine());

/// Whether the app is in the foreground (resumed).
class AppResumed extends Notifier<bool> {
  @override
  bool build() => true;
  void set(bool v) {
    if (v != state) state = v;
  }
}

final appResumedProvider = NotifierProvider<AppResumed, bool>(AppResumed.new);

/// A full-screen route covers the shell (onboarding, the weekly review).
class ShellCovered extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool v) {
    if (ref.mounted && v != state) state = v;
  }
}

final shellCoveredProvider = NotifierProvider<ShellCovered, bool>(ShellCovered.new);

class WakeGate {
  const WakeGate({required this.enabled, required this.onToday, required this.idle});

  /// Settings › Voice › "Hey Planner".
  final bool enabled;

  /// Today is the visible route: app resumed, no sheet, review, settings or
  /// onboarding over it.
  final bool onToday;

  /// Voice is not already open.
  final bool idle;

  bool get armed => enabled && onToday && idle;
}

/// The gate without the voice state (so the voice controller can read it).
final wakeRouteProvider = Provider<WakeGate>((ref) => WakeGate(
      enabled: ref.watch(settingsProvider.select((s) => s.wakeWord)),
      onToday: ref.watch(currentTabProvider) == AppTab.today &&
          ref.watch(appResumedProvider) &&
          ref.watch(sheetProvider) == null &&
          !ref.watch(shellCoveredProvider),
      idle: true,
    ));

final wakeGateProvider = Provider<WakeGate>((ref) {
  final g = ref.watch(wakeRouteProvider);
  return WakeGate(
      enabled: g.enabled, onToday: g.onToday, idle: !ref.watch(voiceControllerProvider.select((v) => v.open)));
});

/// Whether to show the HEY PLANNER caption under the orb. Until a spotter
/// exists it only shows in debug builds (where "Say Hey Planner" simulates it).
final showHeyCaptionProvider = Provider<bool>((ref) =>
    ref.watch(wakeGateProvider).armed &&
    (ref.watch(wakeWordEngineProvider).available || kDebugMode));

/// Starts the spotter while the gate is armed and stops it the moment it is
/// not (pause, route change, sheet, review, settings, voice open).
class WakeWordHost extends ConsumerStatefulWidget {
  const WakeWordHost({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<WakeWordHost> createState() => _WakeWordHostState();
}

class _WakeWordHostState extends ConsumerState<WakeWordHost> {
  late final AppLifecycleListener _life;
  late final WakeWordEngine _engine = ref.read(wakeWordEngineProvider);
  bool _running = false;
  Timer? _arm;

  /// Re-arming waits a moment so the speech recogniser has released the
  /// microphone (Android can't share it between two listeners).
  static const _armDelay = Duration(milliseconds: 400);

  @override
  void initState() {
    super.initState();
    _life = AppLifecycleListener(
      onStateChange: (s) => ref.read(appResumedProvider.notifier).set(s == AppLifecycleState.resumed),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sync(ref.read(wakeGateProvider).armed);
    });
  }

  void _sync(bool armed) {
    if (!_engine.available) return;
    _arm?.cancel();
    if (!armed) {
      if (_running) {
        _running = false;
        _engine.stop();
      }
      return;
    }
    if (_running) return;
    _arm = Timer(_armDelay, () {
      if (!mounted || !ref.read(wakeGateProvider).armed || _running) return;
      _running = true;
      _engine.start(_heard, phrases: _phrases());
    });
  }

  /// Task names on the plan, so the recogniser favours them ("Study
  /// polity" over sound-alikes).
  List<String> _phrases() => {
        for (final t in ref.read(plannerStoreProvider).tasks)
          if (!t.deleted && !t.done) t.title,
      }.take(60).toList();

  /// "Hey Planner": the engine either keeps the microphone and passes on the
  /// rest of the sentence, or releases it first; then voice opens.
  Future<void> _heard() async {
    if (!_running) return;
    _running = false;
    final rest = _engine.takeOver();
    if (rest == null) await _engine.stop();
    if (mounted) {
      ref.read(voiceControllerProvider.notifier).sayHey(input: rest);
    } else {
      await rest?.cancel();
    }
  }

  @override
  void dispose() {
    _arm?.cancel();
    _life.dispose();
    if (_running) _engine.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(wakeGateProvider.select((g) => g.armed), (_, armed) => _sync(armed));
    return widget.child;
  }
}
