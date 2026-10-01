import 'dart:async';
import 'dart:convert';

import 'package:alarm/alarm.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/alarm_prefs.dart';
import '../../domain/category.dart';
import '../../domain/notifications.dart';
import '../../domain/task.dart';
import '../../domain/time.dart';

/// One full-screen alarm, with what its screen shows. Carried as the
/// alarm's payload, so a ringing alarm renders without looking anything up.
class PlannedAlarm {
  const PlannedAlarm({
    required this.id,
    required this.at,
    required this.title,
    this.taskId,
    this.cat = Category.self,
    this.range = '',
    this.next = '',
  });

  final int id;

  /// When it was planned to ring (a snooze moves the ring, not this).
  final DateTime at;
  final String title;
  final String? taskId;
  final Category cat;

  /// "20:00 → 22:00", and what follows ("Then Exercise at 22:15"), or ''.
  final String range, next;

  String get body => range.isEmpty ? 'Time to start.' : 'Time to start: $range.';

  Map<String, Object?> toJson() => {
        'id': id,
        'at': at.millisecondsSinceEpoch,
        'title': title,
        'task': taskId,
        'cat': cat.name,
        'range': range,
        'next': next,
      };

  static PlannedAlarm? tryParse(int id, String? payload) {
    if (payload == null) return null;
    try {
      final j = (jsonDecode(payload) as Map).cast<String, Object?>();
      return PlannedAlarm(
        id: id,
        at: DateTime.fromMillisecondsSinceEpoch((j['at'] as num).toInt()),
        title: j['title'] as String? ?? 'Planner',
        taskId: j['task'] as String?,
        cat: categoryFromName(j['cat'] as String?),
        range: j['range'] as String? ?? '',
        next: j['next'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is PlannedAlarm && jsonEncode(toJson()) == jsonEncode(other.toJson());
  @override
  int get hashCode => Object.hash(id, at, title, taskId);
}

/// A stable alarm id per task (FNV-1a), so re-planning finds the alarm it
/// set before. Kept clear of the notification ids (1000-4999).
int alarmIdFor(String taskId) {
  var h = 0x811c9dc5;
  for (final c in taskId.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0x7fffffff;
  }
  return 10000 + h % 2000000000;
}

/// The task alarms from [notes], with what each screen shows.
List<PlannedAlarm> alarmsFrom(List<PlannedNote> notes, List<Task> tasks) {
  final byId = {for (final t in tasks) t.id: t};
  return [
    for (final n in notes)
      if (n.kind == NoteKind.alarm)
        if (byId[n.taskId] case final t?)
          PlannedAlarm(
            id: alarmIdFor(t.id),
            at: n.at,
            title: t.title,
            taskId: t.id,
            cat: t.cat,
            range: '${fmt(t.start!)} → ${fmt(t.end!)}',
            next: _nextAfter(t, tasks),
          )
        else
          PlannedAlarm(
            id: n.id,
            at: n.at,
            title: n.title,
            cat: n.cat ?? Category.self,
            next: 'A test. Your tasks ring like this.',
          ),
  ];
}

String _nextAfter(Task t, List<Task> tasks) {
  final later = tasks
      .where((o) => o.isLive && !o.done && o.id != t.id && o.day == t.day && o.start! >= t.end!)
      .toList()
    ..sort((a, b) => a.start! - b.start!);
  return later.isEmpty ? '' : 'Then ${later.first.title} at ${fmt(later.first.start!)}';
}

/// Sound and snooze: when these change, every alarm is set again.
class AlarmSound {
  const AlarmSound({this.path, this.fadeSeconds = 0, this.vibrate = true, this.snoozeMinutes = 10});
  AlarmSound.of(AlarmPrefs p)
      : path = p.tonePath,
        fadeSeconds = p.fadeSeconds,
        vibrate = p.vibrate,
        snoozeMinutes = p.snoozeMinutes;
  final String? path;
  final int fadeSeconds, snoozeMinutes;
  final bool vibrate;
  String get key => '$path|$fadeSeconds|$vibrate|$snoozeMinutes';
}

/// An alarm as the platform holds it: its id, when it will ring next, and
/// what it was set from.
class HeldAlarm {
  const HeldAlarm(this.id, this.ringsAt, this.alarm, this.soundKey);
  final int id;
  final DateTime ringsAt;
  final PlannedAlarm? alarm;
  final String soundKey;
}

/// What a sync changes. Alarms whose planned time has passed are ringing or
/// snoozed: they are left alone unless their task is finished or gone (the
/// user answers them on the alarm screen). Everything still ahead follows
/// the plan exactly, and nothing is set for a time already past (a plan
/// computed earlier may still list one).
({List<PlannedAlarm> set, List<int> stop}) alarmDiff({
  required List<HeldAlarm> held,
  required List<PlannedAlarm> plan,
  required Set<String> openTaskIds,
  required DateTime now,
  required String soundKey,
}) {
  final want = {for (final a in plan) a.id: a};
  final stop = <int>[];
  final keep = <int, HeldAlarm>{};
  for (final h in held) {
    final a = h.alarm;
    final inFlight = a != null && !a.at.isAfter(now);
    if (want.containsKey(h.id)) {
      keep[h.id] = h;
    } else if (!inFlight) {
      stop.add(h.id);
    } else if (a.taskId != null && !openTaskIds.contains(a.taskId)) {
      stop.add(h.id);
    }
  }
  bool same(HeldAlarm? h, PlannedAlarm a) =>
      h != null && h.alarm == a && h.soundKey == soundKey && h.ringsAt.isAtSameMomentAs(a.at);
  // Never set a time that has passed: the platform would ring it at once.
  return (set: [for (final a in plan) if (a.at.isAfter(now) && !same(keep[a.id], a)) a], stop: stop);
}

/// Full-screen task alarms. The app uses [PluginAlarmEngine] on Android;
/// tests and other platforms use [NoAlarmEngine].
abstract class AlarmEngine {
  bool get available;
  Future<void> init();

  /// Makes the platform's alarms match [plan] (see [alarmDiff]).
  Future<void> sync(List<PlannedAlarm> plan, AlarmSound sound, {required Set<String> openTaskIds});

  /// The alarms ringing right now.
  Stream<List<PlannedAlarm>> get ringing;
  Future<void> stop(int id);
  Future<void> snooze(int id, Duration d);
}

class NoAlarmEngine implements AlarmEngine {
  NoAlarmEngine({this.available = false});
  @override
  final bool available;
  final held = <int, (PlannedAlarm, DateTime, String)>{};
  final stopped = <int>[];
  final snoozed = <int, Duration>{};
  final _ringing = StreamController<List<PlannedAlarm>>.broadcast();
  final _now = <PlannedAlarm>[];

  /// Test hook: an alarm starts ringing.
  void ring(PlannedAlarm a) {
    _now.add(a);
    _ringing.add(List.of(_now));
  }

  @override
  Future<void> init() async {}

  @override
  Future<void> sync(List<PlannedAlarm> plan, AlarmSound sound, {required Set<String> openTaskIds}) async {
    final d = alarmDiff(
      held: [for (final e in held.entries) HeldAlarm(e.key, e.value.$2, e.value.$1, e.value.$3)],
      plan: plan,
      openTaskIds: openTaskIds,
      now: DateTime.now(),
      soundKey: sound.key,
    );
    for (final id in d.stop) {
      held.remove(id);
    }
    for (final a in d.set) {
      held[a.id] = (a, a.at, sound.key);
    }
  }

  @override
  Stream<List<PlannedAlarm>> get ringing => _ringing.stream;

  @override
  Future<void> stop(int id) async {
    stopped.add(id);
    held.remove(id);
    _now.removeWhere((a) => a.id == id);
    _ringing.add(List.of(_now));
  }

  @override
  Future<void> snooze(int id, Duration d) async {
    snoozed[id] = d;
    _now.removeWhere((a) => a.id == id);
    _ringing.add(List.of(_now));
  }
}

/// The `alarm` plugin: AlarmManager alarm-clock scheduling, a foreground
/// service that plays the tone (fading in if asked) and a full-screen intent
/// that opens Planner over the lock screen.
class PluginAlarmEngine implements AlarmEngine {
  @override
  bool get available => true;

  @override
  Future<void> init() => Alarm.init();

  static const _soundKey = 'plannerSound';

  @override
  Future<void> sync(List<PlannedAlarm> plan, AlarmSound sound, {required Set<String> openTaskIds}) async {
    final existing = await Alarm.getAlarms();
    HeldAlarm held(AlarmSettings s) {
      final m = _decode(s.payload);
      return HeldAlarm(s.id, s.dateTime, PlannedAlarm.tryParse(s.id, m?['alarm'] as String?),
          m?[_soundKey] as String? ?? '');
    }

    final d = alarmDiff(
      held: [for (final s in existing) held(s)],
      plan: plan,
      openTaskIds: openTaskIds,
      now: DateTime.now(),
      soundKey: sound.key,
    );
    for (final id in d.stop) {
      await Alarm.stop(id);
    }
    for (final a in d.set) {
      await Alarm.set(alarmSettings: _settings(a, sound));
    }
    if (kDebugMode && (d.set.isNotEmpty || d.stop.isNotEmpty)) {
      debugPrint('[alarm] set ${d.set.length}, stopped ${d.stop.length}, held ${existing.length}');
    }
  }

  static Map<String, Object?>? _decode(String? p) {
    if (p == null) return null;
    try {
      return (jsonDecode(p) as Map).cast<String, Object?>();
    } catch (_) {
      return null;
    }
  }

  AlarmSettings _settings(PlannedAlarm a, AlarmSound s) => AlarmSettings(
        id: a.id,
        dateTime: a.at,
        assetAudioPath: s.path,
        loopAudio: true,
        vibrate: s.vibrate,
        volumeSettings: s.fadeSeconds > 0
            ? VolumeSettings.fade(fadeDuration: Duration(seconds: s.fadeSeconds))
            : const VolumeSettings.fixed(),
        notificationSettings: NotificationSettings(
          title: a.title,
          body: a.body,
          stopButton: 'Stop',
          androidSnoozeButton: 'Snooze',
        ),
        warningNotificationOnKill: false,
        androidStopAlarmOnTermination: false,
        androidFullScreenIntent: true,
        androidSnoozeDuration: Duration(minutes: s.snoozeMinutes),
        payload: jsonEncode({'alarm': jsonEncode(a.toJson()), _soundKey: s.key}),
      );

  @override
  Stream<List<PlannedAlarm>> get ringing => Alarm.ringing.map((set) => [
        for (final s in set.alarms)
          PlannedAlarm.tryParse(s.id, _decode(s.payload)?['alarm'] as String?) ??
              PlannedAlarm(id: s.id, at: s.dateTime, title: s.notificationSettings.title),
      ]);

  @override
  Future<void> stop(int id) => Alarm.stop(id);

  @override
  Future<void> snooze(int id, Duration d) async {
    final s = await Alarm.getAlarm(id);
    if (s == null) return;
    await Alarm.stop(id);
    await Alarm.set(alarmSettings: s.copyWith(dateTime: DateTime.now().add(d)));
  }
}

/// Overridden in `main` with [PluginAlarmEngine] on Android.
final alarmEngineProvider = Provider<AlarmEngine>((ref) => NoAlarmEngine());
