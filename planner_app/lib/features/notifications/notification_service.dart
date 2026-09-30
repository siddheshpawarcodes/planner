import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../app/state/clock.dart';
import '../../app/state/derived.dart';
import '../../domain/notifications.dart';

/// Local notifications behind an interface: the app uses the plugin, tests
/// and previews use [NoNotifications].
abstract class NotificationService {
  Future<void> init();

  /// Whether the user has allowed notifications (null = not asked yet).
  Future<bool?> granted();
  Future<bool> requestPermission();

  /// Replaces everything scheduled with [notes].
  Future<void> replace(List<PlannedNote> notes);
}

class NoNotifications implements NotificationService {
  NoNotifications();
  final scheduled = <PlannedNote>[];
  bool allowed = true;

  @override
  Future<void> init() async {}
  @override
  Future<bool?> granted() async => allowed;
  @override
  Future<bool> requestPermission() async => allowed;
  @override
  Future<void> replace(List<PlannedNote> notes) async => scheduled
    ..clear()
    ..addAll(notes);
}

/// `flutter_local_notifications` on Android and iOS. Scheduling is inexact
/// (no exact-alarm permission), so "5 minutes before" can drift a little
/// when the phone is dozing.
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
  Future<void> replace(List<PlannedNote> notes) async {
    await init();
    await _plugin.cancelAllPendingNotifications();
    for (final n in notes) {
      await _plugin.zonedSchedule(
        id: n.id,
        scheduledDate: tz.TZDateTime.from(n.at, tz.local),
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: n.title,
        body: n.body,
      );
    }
  }
}

/// Overridden in `main` with [LocalNotifications].
final notificationServiceProvider = Provider<NotificationService>((ref) => NoNotifications());

/// What should be scheduled right now (debug scenarios with a pinned clock
/// schedule nothing, since their times aren't real).
final plannedNotesProvider = Provider<List<PlannedNote>>((ref) {
  final s = ref.watch(settingsProvider);
  final virtual = ref.watch(clockProvider.notifier).isVirtual;
  ref.watch(todayProvider);
  if (virtual) return const [];
  return planNotifications(
    tasks: ref.watch(tasksProvider),
    now: DateTime.now(),
    nextTask: s.notifyNext,
    missed: s.notifyMissed,
    review: s.notifyReview,
  );
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
        await svc.replace(ref.read(plannedNotesProvider));
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
