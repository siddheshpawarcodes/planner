import 'dart:async';

import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../app/state/clock.dart';
import '../../app/state/derived.dart';
import '../../data/alarm_prefs.dart';
import '../../domain/category.dart';
import '../../domain/notifications.dart';
import '../alarm/alarm_engine.dart';

/// Local notifications behind an interface: the app uses the plugin, tests
/// and previews use [NoNotifications].
abstract class NotificationService {
  Future<void> init();

  /// Whether the user has allowed notifications (null = not asked yet).
  Future<bool?> granted();
  Future<bool> requestPermission();

  /// Whether alarms can ring at the exact minute (Android "Alarms &
  /// reminders"). Without it they still fire, a little late when dozing.
  Future<bool> canAlarmExactly();

  /// Opens the system screen that allows exact alarms.
  Future<void> allowExactAlarms();

  /// Replaces everything scheduled with [notes].
  Future<void> replace(List<PlannedNote> notes);
}

class NoNotifications implements NotificationService {
  NoNotifications();
  final scheduled = <PlannedNote>[];
  bool allowed = true, exact = true;

  /// How many times the permission prompt was asked for.
  int asked = 0;

  @override
  Future<void> init() async {}
  @override
  Future<bool?> granted() async => allowed;
  @override
  Future<bool> requestPermission() async {
    asked++;
    return allowed;
  }
  @override
  Future<bool> canAlarmExactly() async => exact;
  @override
  Future<void> allowExactAlarms() async => exact = true;
  @override
  Future<void> replace(List<PlannedNote> notes) async => scheduled
    ..clear()
    ..addAll(notes);
}

/// `flutter_local_notifications` on Android and iOS. Reminders are inexact
/// (they can drift a little when the phone is dozing); task alarms use
/// Android's alarm-clock scheduling when exact alarms are allowed.
class LocalNotifications implements NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'planner',
      'Planner',
      channelDescription: 'Next task, missed check-ins and the weekly review',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    ),
    iOS: DarwinNotificationDetails(),
  );

  /// Task alarms: the alarm sound on the alarm stream, repeating until
  /// dismissed (FLAG_INSISTENT), like an alarm clock.
  static final _alarm = NotificationDetails(
    android: AndroidNotificationDetails(
      'planner_alarm',
      'Task alarms',
      channelDescription: 'Rings when a task is due to start',
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      sound: const UriAndroidNotificationSound('content://settings/system/alarm_alert'),
      playSound: true,
      enableVibration: true,
      additionalFlags: Int32List.fromList(const [4]),
      visibility: NotificationVisibility.public,
    ),
    iOS: const DarwinNotificationDetails(presentSound: true, presentBanner: true),
  );

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  IOSFlutterLocalNotificationsPlugin? get _ios =>
      _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();

  @override
  Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    try {
      final name = (await FlutterTimezone.getLocalTimezone()).identifier;
      tz.setLocalLocation(tz.getLocation(name));
    } catch (_) {
      // Unknown zone: stay on UTC offsets from DateTime, which still line up.
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher_monochrome'),
        // Permission is asked at a calm moment (after onboarding), not at launch.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _ready = true;
  }

  @override
  Future<bool?> granted() async {
    await init();
    if (_android != null) return _android!.areNotificationsEnabled();
    final p = await _ios?.checkPermissions();
    return p?.isEnabled;
  }

  @override
  Future<bool> requestPermission() async {
    await init();
    if (_android != null) return await _android!.requestNotificationsPermission() ?? false;
    return await _ios?.requestPermissions(alert: true, badge: false, sound: true) ?? false;
  }

  @override
  Future<bool> canAlarmExactly() async {
    await init();
    if (_android == null) return true;
    return await _android!.canScheduleExactNotifications() ?? false;
  }

  @override
  Future<void> allowExactAlarms() async {
    await init();
    await _android?.requestExactAlarmsPermission();
  }

  @override
  Future<void> replace(List<PlannedNote> notes) async {
    await init();
    await _plugin.cancelAllPendingNotifications();
    final exact = await canAlarmExactly();
    for (final n in notes) {
      final alarm = n.kind == NoteKind.alarm;
      await _plugin.zonedSchedule(
        id: n.id,
        scheduledDate: tz.TZDateTime.from(n.at, tz.local),
        notificationDetails: alarm ? _alarm : _details,
        androidScheduleMode:
            alarm && exact ? AndroidScheduleMode.alarmClock : AndroidScheduleMode.inexactAllowWhileIdle,
        title: n.title,
        body: n.body,
      );
    }
  }
}

/// Overridden in `main` with [LocalNotifications].
final notificationServiceProvider = Provider<NotificationService>((ref) => NoNotifications());

/// A test alarm (Customise alarm screen › Ring a test, and the developer
/// panel). Scheduling replaces everything on each change, so the test alarm
/// lives in the plan. [cat] picks the look it shows.
final testAlarmProvider = NotifierProvider<TestAlarm, (DateTime, Category)?>(TestAlarm.new);

class TestAlarm extends Notifier<(DateTime, Category)?> {
  @override
  (DateTime, Category)? build() => null;
  void set(DateTime? at, {Category cat = Category.self}) => state = at == null ? null : (at, cat);
}

/// What should be scheduled right now (debug scenarios with a pinned clock
/// schedule nothing, since their times aren't real).
final plannedNotesProvider = Provider<List<PlannedNote>>((ref) {
  final s = ref.watch(settingsProvider);
  final virtual = ref.watch(clockProvider.notifier).isVirtual;
  final test = ref.watch(testAlarmProvider);
  ref.watch(todayProvider);
  if (virtual) return const [];
  final now = DateTime.now();
  return [
    ...planNotifications(
      tasks: ref.watch(tasksProvider),
      now: now,
      nextTask: s.notifyNext,
      alarms: s.taskAlarms,
      missed: s.notifyMissed,
      review: s.notifyReview,
    ),
    if (test != null && test.$1.isAfter(now))
      PlannedNote(3999, NoteKind.alarm, test.$1, 'Test alarm', 'This is how a task alarm rings.', cat: test.$2),
  ];
});

/// Re-plans (debounced) whenever tasks, settings or the day change, and when
/// the app comes back to the foreground.
class NotificationHost extends ConsumerStatefulWidget {
  const NotificationHost({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<NotificationHost> createState() => _NotificationHostState();
}

class _NotificationHostState extends ConsumerState<NotificationHost> {
  Timer? _debounce;
  late final AppLifecycleListener _life;

  @override
  void initState() {
    super.initState();
    _life = AppLifecycleListener(onResume: _schedule);
    WidgetsBinding.instance.addPostFrameCallback((_) => _schedule());
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 1), () async {
      if (!mounted) return;
      final svc = ref.read(notificationServiceProvider);
      try {
        if (await svc.granted() != true) return;
        var notes = ref.read(plannedNotesProvider);
        // Full-screen style: task alarms belong to the alarm engine (which
        // rings, fades in and opens the alarm screen); the rest stay here.
        final prefs = ref.read(settingsProvider).alarm;
        final engine = ref.read(alarmEngineProvider);
        final full = engine.available && prefs.style == AlarmStyle.fullScreen;
        final tasks = ref.read(tasksProvider);
        await engine.sync(full ? alarmsFrom(notes, tasks) : const [], AlarmSound.of(prefs),
            openTaskIds: {for (final t in tasks) if (t.isLive && !t.done) t.id});
        if (full) notes = [for (final n in notes) if (n.kind != NoteKind.alarm) n];
        await svc.replace(notes);
      } catch (e) {
        if (kDebugMode) debugPrint('[notifications] $e');
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _life.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(plannedNotesProvider, (_, _) => _schedule());
    return widget.child;
  }
}
