import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One of the phone's alarm tones.
class AlarmTone {
  const AlarmTone(this.title, this.uri);
  final String title, uri;
}

/// The Android side of full-screen alarms (`MainActivity`, channel
/// `planner/alarm`): the lock screen, alarm tones and the full-screen
/// permission. [NoAlarmPlatform] stands in for tests and other platforms.
abstract class AlarmPlatform {
  /// Planner was opened by a ringing alarm (so it shows over the lock screen).
  Future<bool> launchedByAlarm();

  /// Show over the lock screen for a ring that reached an open app.
  Future<void> showOverLock();

  /// Answered: stop showing over the lock screen, and step back to whatever
  /// the alarm interrupted when it opened Planner.
  Future<void> release();

  /// Start now: unlock (asking if needed) and stay. False when the user
  /// cancelled unlocking.
  Future<bool> unlockAndStay();

  /// Planner's alarm screen is up: take down the system's heads-up banner
  /// for alarm [id] (the notification stays, quietly, in the shade).
  Future<void> quietBanner(int id, String title, String body);

  Future<List<AlarmTone>> tones();

  /// Copies a tone into Planner's files; the path, or null if it failed.
  Future<String?> copyTone(AlarmTone t);

  /// Plays [uri] (a tone uri or a file path; null = the phone's default) once.
  Future<void> preview(String? uri);
  Future<void> stopPreview();

  /// Android 14+: "Full screen notifications" for Planner.
  Future<bool> canFullScreen();
  Future<void> allowFullScreen();
}

class MethodAlarmPlatform implements AlarmPlatform {
  static const _ch = MethodChannel('planner/alarm');

  Future<T?> _call<T>(String m, [Map<String, Object?>? args]) async {
    try {
      return await _ch.invokeMethod<T>(m, args);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<bool> launchedByAlarm() async => await _call<bool>('launchedByAlarm') ?? false;
  @override
  Future<void> showOverLock() => _call('showOverLock');
  @override
  Future<void> release() => _call('release');
  @override
  Future<bool> unlockAndStay() async => await _call<bool>('unlockAndStay') ?? true;

  @override
  Future<void> quietBanner(int id, String title, String body) =>
      _call('quietBanner', {'id': id, 'title': title, 'body': body});

  @override
  Future<List<AlarmTone>> tones() async {
    final l = await _call<List<Object?>>('tones') ?? const [];
    return [
      for (final e in l.cast<Map<Object?, Object?>>())
        AlarmTone(e['title'] as String? ?? 'Tone', e['uri'] as String? ?? ''),
    ];
  }

  @override
  Future<String?> copyTone(AlarmTone t) => _call<String>('copyTone', {'uri': t.uri, 'name': t.title});
  @override
  Future<void> preview(String? uri) => _call('preview', {'uri': uri});
  @override
  Future<void> stopPreview() => _call('stopPreview');
  @override
  Future<bool> canFullScreen() async => await _call<bool>('canFullScreen') ?? true;
  @override
  Future<void> allowFullScreen() => _call('allowFullScreen');
}

class NoAlarmPlatform implements AlarmPlatform {
  NoAlarmPlatform({this.toneList = const [], this.fullScreen = true});
  final List<AlarmTone> toneList;
  bool fullScreen;
  int released = 0, stayed = 0, overLock = 0;
  final quieted = <int>[];
  String? previewing;

  @override
  Future<bool> launchedByAlarm() async => false;
  @override
  Future<void> showOverLock() async => overLock++;
  @override
  Future<void> release() async => released++;
  @override
  Future<bool> unlockAndStay() async {
    stayed++;
    return true;
  }

  @override
  Future<void> quietBanner(int id, String title, String body) async => quieted.add(id);
  @override
  Future<List<AlarmTone>> tones() async => toneList;
  @override
  Future<String?> copyTone(AlarmTone t) async => '/tones/${t.title}.tone';
  @override
  Future<void> preview(String? uri) async => previewing = uri ?? 'default';
  @override
  Future<void> stopPreview() async => previewing = null;
  @override
  Future<bool> canFullScreen() async => fullScreen;
  @override
  Future<void> allowFullScreen() async => fullScreen = true;
}

/// Overridden in `main` with [MethodAlarmPlatform] on Android.
final alarmPlatformProvider = Provider<AlarmPlatform>((ref) => NoAlarmPlatform());
