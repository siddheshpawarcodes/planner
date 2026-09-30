import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:porcupine_flutter/porcupine_error.dart';
import 'package:porcupine_flutter/porcupine_manager.dart';

import 'wake_word.dart';

/// Build-time configuration. The AccessKey is never in the source: pass it
/// with `--dart-define-from-file=config/secrets.json` (git-ignored; see
/// `config/secrets.example.json`) or `--dart-define=PICOVOICE_ACCESS_KEY=…`.
const kPicovoiceAccessKey = String.fromEnvironment('PICOVOICE_ACCESS_KEY');

/// The trained "Hey Planner" keyword, one file per platform (git-ignored;
/// drop the files exported from the Picovoice Console here).
String keywordAssetFor(TargetPlatform p) =>
    p == TargetPlatform.iOS ? 'assets/wake/hey_planner_ios.ppn' : 'assets/wake/hey_planner_android.ppn';

/// Porcupine (Picovoice) on-device keyword spotting for "Hey Planner". It
/// only runs while `WakeWordHost` arms it (Today visible, app resumed, voice
/// idle), never in the background, and only once the microphone is allowed.
class PorcupineWakeWordEngine implements WakeWordEngine {
  PorcupineWakeWordEngine._(this._key, this._keyword, this.unavailableReason);

  final String _key, _keyword;
  PorcupineManager? _manager;
  VoidCallback? _onWake;
  String? _failure;

  @override
  String? unavailableReason;

  @override
  bool get available => unavailableReason == null && _failure == null;

  /// Checks the key and the keyword model before the app starts.
  static Future<PorcupineWakeWordEngine> create({String accessKey = kPicovoiceAccessKey, TargetPlatform? platform}) async {
    final keyword = keywordAssetFor(platform ?? defaultTargetPlatform);
    String? why;
    if (kIsWeb || !(defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
      why = 'The wake phrase works on Android and iOS.';
    } else if (accessKey.isEmpty) {
      why = 'No Picovoice AccessKey in this build.';
    } else {
      try {
        await rootBundle.load(keyword);
      } catch (_) {
        why = 'No “Hey Planner” keyword model at $keyword.';
      }
    }
    if (why != null && kDebugMode) debugPrint('[wake] off: $why');
    return PorcupineWakeWordEngine._(accessKey, keyword, why);
  }

  @override
  Future<void> start(VoidCallback onWake) async {
    if (!available) return;
    _onWake = onWake;
    // Never ask for the microphone just to arm the wake phrase.
    if (!await Permission.microphone.isGranted) return;
    try {
      _manager ??= await PorcupineManager.fromKeywordPaths(
        _key,
        [_keyword],
        (_) => _onWake?.call(),
        sensitivities: const [0.6],
        errorCallback: (e) => _fail(e),
      );
      await _manager!.start();
    } on PorcupineException catch (e) {
      _fail(e);
    }
  }

  void _fail(PorcupineException e) {
    // A bad key or model won't fix itself: stop trying for this session.
    _failure = e.message ?? e.runtimeType.toString();
    if (kDebugMode) debugPrint('[wake] ${e.runtimeType}: ${e.message}');
    _manager?.delete();
    _manager = null;
  }

  @override
  Future<void> stop() async {
    try {
      await _manager?.stop();
    } on PorcupineException catch (e) {
      if (kDebugMode) debugPrint('[wake] stop: ${e.message}');
    }
  }
}
