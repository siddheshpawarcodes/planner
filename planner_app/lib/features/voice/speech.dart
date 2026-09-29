import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// What a listening session reports.
class SpeechCallbacks {
  const SpeechCallbacks({required this.onWords, required this.onLevel, required this.onDone});

  /// The transcript so far (partial results replace it).
  final void Function(String text) onWords;

  /// Mic level 0..1 for the orb (RMS × 7, clamped, as in the prototype).
  final void Function(double level) onLevel;

  /// Listening ended; [text] is the final transcript (may be empty).
  final void Function(String text) onDone;
}

enum MicAccess { granted, denied, permanentlyDenied, unavailable }

/// Speech-to-text behind an interface so the voice flow runs the same with
/// the device recogniser or the scripted demo voice.
abstract class SpeechInput {
  Future<MicAccess> prepare();
  Future<void> listen(SpeechCallbacks cb);
  Future<void> stop();
  Future<void> cancel();

  /// Asks again, or opens system settings when permanently denied.
  Future<MicAccess> requestAccess();

  /// Live input (real mic) vs scripted.
  bool get isLive;
}

/// The device recogniser (`speech_to_text`). Its sound-level stream drives
/// the orb, so no second recorder competes for the microphone.
class DeviceSpeech implements SpeechInput {
  final _stt = SpeechToText();
  bool _ready = false;
  String _last = '';
  SpeechCallbacks? _cb;
  bool _doneSent = false;

  @override
  bool get isLive => true;

  @override
  Future<MicAccess> prepare() async {
    final mic = await Permission.microphone.status;
    if (mic.isPermanentlyDenied) return MicAccess.permanentlyDenied;
    try {
      _ready = _ready ||
          await _stt.initialize(
            onStatus: _onStatus,
            onError: (_) => _finish(),
          );
    } catch (_) {
      return MicAccess.unavailable;
    }
    if (!_ready) {
      final again = await Permission.microphone.status;
      return again.isPermanentlyDenied ? MicAccess.permanentlyDenied : MicAccess.denied;
    }
    return MicAccess.granted;
  }

  void _onStatus(String s) {
    if (s == SpeechToText.doneStatus || s == SpeechToText.notListeningStatus) _finish();
  }

  void _finish() {
    if (_doneSent) return;
    _doneSent = true;
    _cb?.onDone(_last);
  }

  @override
  Future<void> listen(SpeechCallbacks cb) async {
    _cb = cb;
    _last = '';
    _doneSent = false;
    await _stt.listen(
      onResult: (SpeechRecognitionResult r) {
        _last = r.recognizedWords;
        cb.onWords(_last);
        if (r.finalResult) _finish();
      },
      onSoundLevelChange: (db) {
        // speech_to_text reports roughly −2…10 dB; map onto 0..1.
        cb.onLevel(math.max(0, math.min(1, (db + 2) / 12)));
      },
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        listenFor: const Duration(seconds: 20),
        pauseFor: const Duration(milliseconds: 1600),
      ),
    );
  }

  @override
  Future<void> stop() => _stt.stop();

  @override
  Future<void> cancel() async {
    _doneSent = true;
    await _stt.cancel();
  }

  @override
  Future<MicAccess> requestAccess() async {
    final st = await Permission.microphone.request();
    if (st.isPermanentlyDenied) {
      await openAppSettings();
      return MicAccess.permanentlyDenied;
    }
    if (!st.isGranted) return MicAccess.denied;
    await Permission.speech.request();
    return prepare();
  }
}

/// The prototype's demo voice: speaks one of the nine lines word by word
/// (every 215ms, scaled under reduced motion).
class DemoSpeech implements SpeechInput {
  DemoSpeech(this.line, {this.factor = 1, this.allowed = true});
  final String Function() line;
  final double factor;
  bool allowed;
  Timer? _t;

  @override
  bool get isLive => false;

  @override
  Future<MicAccess> prepare() async => allowed ? MicAccess.granted : MicAccess.denied;

  @override
  Future<void> listen(SpeechCallbacks cb) async {
    final words = line().split(' ');
    var n = 0;
    _t?.cancel();
    _t = Timer(Duration(milliseconds: (150 * factor).round()), () {
      _t = Timer.periodic(Duration(milliseconds: (215 * factor).round()), (t) {
        n++;
        cb.onWords(words.take(n).join(' '));
        if (n >= words.length) {
          t.cancel();
          cb.onDone(words.join(' '));
        }
      });
    });
  }

  @override
  Future<void> stop() async => _t?.cancel();

  @override
  Future<void> cancel() async => _t?.cancel();

  @override
  Future<MicAccess> requestAccess() async {
    allowed = true;
    return MicAccess.granted;
  }
}

/// Debug controls mirroring the prototype panel: demo line, mic allowed,
/// live mic.
class VoiceDebug {
  const VoiceDebug({this.line = 0, this.micAllowed = true, this.live = false});
  final int line;
  final bool micAllowed;
  final bool live;
  VoiceDebug copyWith({int? line, bool? micAllowed, bool? live}) => VoiceDebug(
      line: line ?? this.line, micAllowed: micAllowed ?? this.micAllowed, live: live ?? this.live);
}

class VoiceDebugController extends Notifier<VoiceDebug> {
  @override
  VoiceDebug build() => const VoiceDebug();
  void set(VoiceDebug Function(VoiceDebug v) f) => state = f(state);
}

final voiceDebugProvider =
    NotifierProvider<VoiceDebugController, VoiceDebug>(VoiceDebugController.new);

/// The live device recogniser, created once.
final deviceSpeechProvider = Provider<DeviceSpeech>((ref) => DeviceSpeech());
