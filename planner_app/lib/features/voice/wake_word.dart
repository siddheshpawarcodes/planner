import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/state/derived.dart';
import '../../app/state/ui_state.dart';
import 'voice_controller.dart';

/// An on-device keyword spotter for "Hey Planner" (README 6.3). It runs only
/// while [wakeGateProvider] says the wake phrase is armed; there is no
/// background service.
abstract class WakeWordEngine {
  /// False until a spotter (and its keyword model) is configured.
  bool get available;

  /// Starts listening for the phrase; [onWake] fires once per detection.
  Future<void> start(VoidCallback onWake);
  Future<void> stop();
}

/// No spotter configured yet: tap-to-talk only. (A Porcupine or similar
/// engine replaces this once a key and keyword model exist.)
class NoWakeWordEngine implements WakeWordEngine {
  const NoWakeWordEngine();
  @override
  bool get available => false;
  @override
  Future<void> start(VoidCallback onWake) async {}
  @override
  Future<void> stop() async {}
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
    if (armed == _running || !_engine.available) return;
    _running = armed;
    if (armed) {
      _engine.start(() => ref.read(voiceControllerProvider.notifier).sayHey());
    } else {
      _engine.stop();
    }
  }

  @override
  void dispose() {
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
