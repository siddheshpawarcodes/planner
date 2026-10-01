import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'wake_word.dart';

/// "Hey Planner" on Android with Vosk, free and fully offline (`VoskWake`
/// in the Android app, channels `planner/wake` and `planner/wake/events`).
/// Vosk is a speech recogniser restricted to a small grammar: the wake
/// phrase plus near-miss decoys, so "hey planet" or "okay planner" don't
/// wake it. It runs only while `WakeWordHost` arms it (Today visible, app
/// resumed, voice idle), and only once the microphone is allowed.
class VoskWakeWordEngine implements WakeWordEngine {
  VoskWakeWordEngine._(this.unavailableReason);

  static const _ch = MethodChannel('planner/wake');
  static const _events = EventChannel('planner/wake/events');

  StreamSubscription<Object?>? _sub;
  VoidCallback? _onWake;

  @override
  final String? unavailableReason;

  @override
  bool get available => unavailableReason == null;

  /// Asks the Android side whether this build carries the model.
  static Future<VoskWakeWordEngine> create() async {
    String? why;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      why = 'The wake phrase works on Android.';
    } else {
      try {
        why = await _ch.invokeMethod<String>('status');
      } on MissingPluginException {
        why = 'No wake-word engine in this build.';
      } on PlatformException catch (e) {
        why = e.message ?? 'The wake-word engine failed to start.';
      }
    }
    if (why != null && kDebugMode) debugPrint('[wake] off: $why');
    final e = VoskWakeWordEngine._(why);
    if (e.available) {
      e._sub = _events.receiveBroadcastStream().listen((v) {
        if (v == 'wake') {
          if (kDebugMode) debugPrint('[wake] heard “Hey Planner”');
          e._onWake?.call();
        }
      });
    }
    return e;
  }

  @override
  Future<void> start(VoidCallback onWake) async {
    if (!available) return;
    _onWake = onWake;
    // Never ask for the microphone just to arm the wake phrase.
    if (!await Permission.microphone.isGranted) return;
    try {
      await _ch.invokeMethod('start');
    } on PlatformException catch (e) {
      if (kDebugMode) debugPrint('[wake] start: ${e.message}');
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _ch.invokeMethod('stop');
    } on PlatformException catch (e) {
      if (kDebugMode) debugPrint('[wake] stop: ${e.message}');
    }
  }

  void dispose() => _sub?.cancel();
}
