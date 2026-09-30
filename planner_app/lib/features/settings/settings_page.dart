import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../app/dev/dev_panel.dart';
import '../../app/state/actions.dart';
import '../../app/state/derived.dart';
import '../../app/state/store.dart';
import '../../app/theme/planner_theme.dart';
import '../../data/settings.dart';
import '../../domain/time.dart';
import '../../widgets/controls.dart';
import '../../widgets/icons.dart';
import '../../app/state/ui_state.dart';
import '../notifications/notification_service.dart';
import '../voice/wake_word.dart';
import 'drive_page.dart';

/// Settings (README 6.10): a push page with Routine, Notifications, Voice,
/// Appearance, Data and statistics, and About. Debug builds add the
/// developer panel at the end.
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late final AppLifecycleListener _life;
  PermissionStatus? _mic;
  bool? _notify;
  bool _exact = true;

  /// "Delete all data" is armed by the first tap for 4 seconds.
  bool _armed = false;

  @override
  void initState() {
    super.initState();
    _life = AppLifecycleListener(onResume: _refresh);
    _refresh();
  }

  @override
  void dispose() {
    _life.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    PermissionStatus? mic;
    bool? notify;
    var exact = true;
    try {
      mic = await Permission.microphone.status;
    } catch (_) {}
    try {
      notify = await ref.read(notificationServiceProvider).granted();
      exact = await ref.read(notificationServiceProvider).canAlarmExactly();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _mic = mic;
        _notify = notify;
        _exact = exact;
      });
    }
  }

  Future<void> _allowMic() async {
    final s = await Permission.microphone.request();
    if (s.isPermanentlyDenied) await openAppSettings();
    await _refresh();
  }

  Future<void> _allowNotifications() async {
    final ok = await ref.read(notificationServiceProvider).requestPermission();
    if (!ok) await openAppSettings();
    await _refresh();
  }

  void _set(Settings Function(Settings s) f) {
    final store = ref.read(plannerStoreProvider.notifier);
    store.setSettings(f(ref.read(settingsProvider)));
  }

  void _delete() {
    if (_armed) {
      setState(() => _armed = false);
      ref.read(actionsProvider).deleteAllData();
      return;
    }
    setState(() => _armed = true);
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() => _armed = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = PlannerColors.of(context);
    final s = ref.watch(settingsProvider);
    final r = ref.watch(routineProvider);
    final act = ref.read(actionsProvider);
    final wake = ref.read(wakeWordEngineProvider);
    final line = BorderSide(color: c.ln);

    Widget heading(String t) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Semantics(header: true, child: Text(t, style: PlannerType.bricolage600(15, color: c.tx))),
        );
    Widget row(String k, Widget v, {double min = 44}) => Container(
          constraints: BoxConstraints(minHeight: min),
          decoration: BoxDecoration(border: Border(top: line)),
          child: Row(children: [
            Expanded(child: Text(k, style: PlannerType.body(size: 14, color: c.t2))),
            v,
          ]),
        );
    Widget value(String v, {bool mono = false}) => Text(v,
        style: mono ? PlannerType.time(size: 13, color: c.tx) : PlannerType.body(size: 14, color: c.tx));
    Widget toggle(String title, String sub, bool on, ValueChanged<bool> set, {String? label}) => Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(border: Border(top: line)),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: PlannerType.ui(14, color: c.tx)),
                const SizedBox(height: 2),
                Text(sub, style: PlannerType.body(size: 12, color: c.t3).copyWith(height: 1.4)),
              ]),
            ),
            const SizedBox(width: 12),
            PlannerSwitch(value: on, onChanged: set, label: label ?? title),
          ]),
        );
    Widget link(String label, VoidCallback onTap, {Color? color, Widget? trailing}) => Pressable(
          onTap: onTap,
          label: label,
          radius: 4,
          pressedScale: 0.99,
          excludeChildSemantics: true,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            decoration: BoxDecoration(border: Border(top: line)),
            child: Row(children: [
              Expanded(child: Text(label, style: PlannerType.ui(14, color: color ?? c.tx))),
              ?trailing,
            ]),
          ),
        );
    Widget seg<T>(String label, List<(T, String)> options, T v, ValueChanged<T> set) =>
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(label, style: PlannerType.body(size: 13, color: c.t2)),
          const SizedBox(height: 6),
          SegmentedPill<T>(options: options, value: v, onChanged: set, height: 40, label: label),
        ]);
    const gap = SizedBox(height: 26);
    final micOk = _mic?.isGranted ?? false;
    final rows = [
      ('Wake', fmt(r.wake)),
      ('Work', r.noFixedWork ? 'No fixed hours' : '${fmt(r.workStart)} → ${fmt(r.workEnd)}'),
      ('Sleep', fmt(r.sleep)),
      ('Commitments', '${r.commitments.where((x) => x.on).length} recurring'),
    ];

    final driveOpen = ref.watch(drivePageOpenProvider);
    final openDrive = ref.read(drivePageOpenProvider.notifier);
    final root = ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
      children: [
        SizedBox(
          height: 44,
          child: Row(children: [
            Expanded(
              child: Semantics(header: true, child: Text('Settings', style: PlannerType.screenTitle(color: c.tx))),
            ),
            PlannerIconButton(icon: PIcon.close, label: 'Close settings', onTap: act.closeSettings, color: c.tx, size: 20),
          ]),
        ),
        gap,

        heading('Routine'),
        for (final (k, v) in rows)
          Semantics(
            label: '$k, ${v.replaceAll('→', 'to')}',
            excludeSemantics: true,
            child: row(k, value(v, mono: k == 'Wake' || k == 'Sleep' || (k == 'Work' && !r.noFixedWork))),
          ),
        link('Edit routine', act.editRoutine, trailing: PlannerIcon(PIcon.chev, size: 16, color: c.t3, stroke: 1.6)),
        gap,

        heading('Notifications'),
        toggle('Next task', '5 minutes before it starts', s.notifyNext, (v) => _set((x) => x.copyWith(notifyNext: v))),
        toggle('Missed tasks', 'One gentle check-in, never a pile-up', s.notifyMissed,
            (v) => _set((x) => x.copyWith(notifyMissed: v))),
        toggle('Task alarms', 'Rings when each task starts. Completing or moving a task updates it.', s.taskAlarms,
            (v) => _set((x) => x.copyWith(taskAlarms: v))),
        if (s.taskAlarms && !_exact)
          row(
            'Allow alarms to ring on time',
            SecondaryPill(
              label: 'Allow',
              height: 32,
              padding: 12,
              onTap: () async {
                await ref.read(notificationServiceProvider).allowExactAlarms();
                await _refresh();
              },
            ),
            min: 48,
          ),
        toggle('Weekly review', 'Sunday at 21:00', s.notifyReview, (v) => _set((x) => x.copyWith(notifyReview: v))),
        if (_notify == false)
          row(
            'Notifications are off for Planner',
            SecondaryPill(label: 'Allow', height: 32, padding: 12, onTap: _allowNotifications),
            min: 48,
          ),
        gap,

        heading('Voice'),
        toggle(
          '“Hey Planner”',
          wake.available
              ? 'Works only while Today is open on screen. Planner never listens in the background.'
              : 'Not set up on this build, so tap the orb to talk.'
                  '${kDebugMode ? ' (${wake.unavailableReason})' : ''}',
          s.wakeWord,
          (v) => _set((x) => x.copyWith(wakeWord: v)),
          label: 'Wake phrase',
        ),
        row(
          'Microphone',
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text(micOk ? 'Allowed' : 'Not allowed', style: PlannerType.body(size: 13, color: c.tx)),
            if (!micOk) ...[
              const SizedBox(width: 10),
              SecondaryPill(label: 'Allow', height: 32, padding: 12, onTap: _allowMic),
            ],
          ]),
          min: 48,
        ),
        row('Language', value(s.language)),
        gap,

        heading('Appearance'),
        seg<ThemeChoice>('Theme', const [(ThemeChoice.system, 'System'), (ThemeChoice.dark, 'Dark'), (ThemeChoice.light, 'Light')],
            s.theme, (v) => _set((x) => x.copyWith(theme: v))),
        const SizedBox(height: 12),
        seg<MotionChoice>(
            'Motion',
            const [(MotionChoice.system, 'System'), (MotionChoice.reduced, 'Reduced'), (MotionChoice.full, 'Full')],
            s.motion,
            (v) => _set((x) => x.copyWith(motion: v))),
        const SizedBox(height: 12),
        seg<TodayView>('Today opens as', const [(TodayView.strip, 'Strip'), (TodayView.dial, 'Dial')], s.todayView,
            (v) => _set((x) => x.copyWith(todayView: v))),
        gap,

        heading('Backup'),
        DriveRow(onTap: () => openDrive.set(true)),
        gap,

        heading('Data and statistics'),
        row('Week starts on', value('Monday')),
        toggle('Count skipped as missed', 'Off: skipping is a decision, not a failure', s.countSkippedAsMissed,
            (v) => _set((x) => x.copyWith(countSkippedAsMissed: v))),
        link('Export as JSON', act.exportJson, trailing: Text('.json', style: PlannerType.time(size: 12, color: c.t3))),
        Semantics(
          liveRegion: _armed,
          child: link(_armed ? 'Tap again to erase everything on this phone' : 'Delete all data', _delete,
              color: _armed ? Category.body.color : c.t2),
        ),
        gap,

        heading('About'),
        Text(
          'Planner 1.0. Local-first: your plan lives on this phone and works offline. '
          'Google Drive only keeps a private backup.',
          style: PlannerType.body(size: 13, color: c.t2).copyWith(height: 1.5),
        ),
        if (kDebugMode) ...[const SizedBox(height: 10), const DevPanel()],
      ],
    );
    final reduced = PlannerMotion.reduced(context);
    // Drive slides in from the right; the root moves 24% left and fades.
    return PopScope(
      canPop: !driveOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) openDrive.set(false);
      },
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: driveOpen ? 1 : 0),
        duration: PlannerMotion.ms(context, 520),
        curve: PlannerMotion.settleCurve,
        builder: (context, v, _) => Stack(children: [
          IgnorePointer(
            ignoring: driveOpen,
            child: ExcludeSemantics(
              excluding: driveOpen,
              child: Opacity(
                opacity: reduced ? 1 - v : (1 - v * 1.4).clamp(0.0, 1.0),
                child: FractionalTranslation(translation: Offset(reduced ? 0 : -0.24 * v, 0), child: root),
              ),
            ),
          ),
          if (v > 0.001)
            FractionalTranslation(
              translation: Offset(reduced ? 0 : 1 - v, 0),
              child: Opacity(
                opacity: reduced ? v : 1,
                child: ColoredBox(color: c.bg, child: DrivePage(onBack: () => openDrive.set(false))),
              ),
            ),
        ]),
      ),
    );
  }
}
