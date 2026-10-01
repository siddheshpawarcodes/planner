import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'speech.dart';
import 'wake_word.dart';

/// "Hey Planner" on Android with Vosk, free and fully offline (`VoskWake`
/// in the Android app, channels `planner/wake` and `planner/wake/events`).
/// A grammar-limited recogniser spots the phrase; when it is said mid-
/// sentence, an unrestricted one transcribes the rest of that sentence, so a
/// request said in one breath arrives whole ([VoskRequest]). It runs only
/// while `WakeWordHost` arms it (Today visible, app resumed, voice idle),
/// and only once the microphone is allowed.
class VoskWakeWordEngine implements WakeWordEngine {
  VoskWakeWordEngine._(this.unavailableReason);

  static const _ch = MethodChannel('planner/wake');
  static const _events = EventChannel('planner/wake/events');

  StreamSubscription<Object?>? _sub;
  VoidCallback? _onWake;

  /// The request being heard since the last wake, until voice takes it.
  VoskRequest? _request;

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
    if (e.available) e._sub = _events.receiveBroadcastStream().listen((v) => e._event('$v'));
    return e;
  }

  void _event(String v) {
    final colon = v.indexOf(':');
    final kind = colon < 0 ? v : v.substring(0, colon);
    final arg = colon < 0 ? '' : v.substring(colon + 1);
    switch (kind) {
      case 'wake':
        if (kDebugMode) debugPrint('[wake] heard “Hey Planner”');
        _request = VoskRequest(() => _call('endRequest'));
        _onWake?.call();
      case 'partial':
        _request?.words(arg);
        _active?.words(arg);
      case 'level':
        _active?.level(double.tryParse(arg) ?? 0);
      case 'request':
        if (kDebugMode) debugPrint('[wake] request “$arg”');
        (_request ?? _active)?.done(arg);
        _active = null;
      case 'handoff':
        if (kDebugMode) debugPrint('[wake] handing the request to the device recogniser');
        (_request ?? _active)?.handOver();
        _active = null;
    }
  }

  /// The request voice took over, still receiving events.
  VoskRequest? _active;

  @override
  HandOverSpeech? takeOver() {
    final r = _request;
    _request = null;
    _active = r;
    return r;
  }

  Future<void> _call(String m) async {
    try {
      await _ch.invokeMethod(m);
    } on PlatformException catch (e) {
      if (kDebugMode) debugPrint('[wake] $m: ${e.message}');
    }
  }

  @override
  Future<void> start(VoidCallback onWake, {List<String> phrases = const []}) async {
    if (!available) return;
    _onWake = onWake;
    // Never ask for the microphone just to arm the wake phrase.
    if (!await Permission.microphone.isGranted) return;
    try {
      await _ch.invokeMethod('start', {'phrases': phrases});
    } on PlatformException catch (e) {
      if (kDebugMode) debugPrint('[wake] start: ${e.message}');
    }
  }

  @override
  Future<void> stop() => _call('stop');

  void dispose() => _sub?.cancel();
}

/// The rest of a sentence Vosk is transcribing after the wake phrase. It
/// keeps what arrives before the voice screen starts listening (the orb's
/// wake animation takes most of a second), then passes it on; if only the
/// wake phrase was said it hands the request to [fallback].
class VoskRequest implements HandOverSpeech {
  VoskRequest(this._end);

  final Future<void> Function() _end;

  @override
  SpeechInput Function()? fallback;

  SpeechCallbacks? _cb;
  String _words = '';
  String? _done;
  bool _handOver = false, _finished = false;
  SpeechInput? _delegate;

  void words(String t) {
    _words = t;
    _cb?.onWords(t);
  }

  void level(double v) => _cb?.onLevel(v);

  void done(String t) {
    _done = t;
    _finish(t);
  }

  void _finish(String t) {
    final cb = _cb;
    if (cb == null || _finished) return;
    _finished = true;
    cb.onDone(t);
  }

  void handOver() {
    _handOver = true;
    if (_cb != null) _startFallback();
  }

  Future<void> _startFallback() async {
    final make = fallback;
    final cb = _cb;
    if (make == null || cb == null || _delegate != null) return;
    final d = _delegate = make();
    if (await d.prepare() != MicAccess.granted) return _finish('');
    await d.listen(cb);
  }

  @override
  bool get isLive => true;

  @override
  Future<MicAccess> prepare() async => MicAccess.granted;

  @override
  Future<MicAccess> requestAccess() async => MicAccess.granted;

  @override
  Future<void> listen(SpeechCallbacks cb) async {
    _cb = cb;
    if (_words.isNotEmpty) cb.onWords(_words);
    if (_done != null) {
      _finish(_done!);
    } else if (_handOver) {
      await _startFallback();
    }
  }

  /// Finish now with what has been heard.
  @override
  Future<void> stop() async {
    if (_delegate != null) return _delegate!.stop();
    await _end();
    _finish(_words);
  }

  @override
  Future<void> cancel() async {
    _finished = true;
    await _delegate?.cancel();
    await _end();
  }
}
