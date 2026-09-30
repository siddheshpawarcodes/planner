import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/state/clock.dart';
import '../../app/state/derived.dart';
import '../../app/state/store.dart';
import '../../app/state/ui_state.dart';
import '../../app/theme/planner_theme.dart';
import '../../data/backup/sync.dart';
import '../../data/snapshot.dart';
import '../../domain/time.dart';
import '../../widgets/controls.dart';
import '../../widgets/icons.dart';

/// Settings › Google Drive (README 6.11): every state of the backup, with
/// the restore confirmation as a sheet over the page.
class DrivePage extends ConsumerWidget {
  const DrivePage({super.key, required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = PlannerColors.of(context);
    final s = ref.watch(syncProvider);
    final sync = ref.read(syncProvider.notifier);
    final data = ref.watch(plannerStoreProvider);
    final online = ref.watch(onlineProvider);
    final now = DateTime.now();
    final line = BorderSide(color: c.ln);
    final offline = !online && s.connected && s.status != SyncStatus.conflict;
    final status = driveStatusText(s, data, online: online, now: now);

    Widget para(String t, {bool strong = false}) => Text(t,
        style: PlannerType.body(size: strong ? 15 : 13, color: strong ? c.tx : c.t2).copyWith(height: 1.5));
    Widget row(String k, Widget v, {bool first = false}) => Container(
          constraints: const BoxConstraints(minHeight: 48),
          decoration: BoxDecoration(border: first ? null : Border(top: line)),
          child: Row(children: [
            Expanded(child: Text(k, style: PlannerType.body(size: 14, color: c.t2))),
            v,
          ]),
        );
    Widget bar(double? p, double h) => ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: SizedBox(
            height: h,
            child: p == null
                ? LoadingSweep(color: c.tx, height: h)
                : Stack(children: [
                    Positioned.fill(child: ColoredBox(color: c.ln)),
                    FractionallySizedBox(
                      widthFactor: p,
                      heightFactor: 1,
                      alignment: Alignment.centerLeft,
                      child: ColoredBox(color: c.tx),
                    ),
                  ]),
          ),
        );

    final body = <Widget>[];
    switch (s.status) {
      case SyncStatus.off:
        body.addAll([
          para('Planner keeps everything on this phone. Drive keeps a private copy, so you can restore it on a new phone.',
              strong: true),
          const SizedBox(height: 14),
          para('Planner only sees the one backup file it creates. It can’t read the rest of your Drive.'),
          const SizedBox(height: 14),
          PrimaryPill(label: 'Connect Google Drive', height: 52, expand: true, onTap: sync.connect),
        ]);
      case SyncStatus.connecting:
        body.addAll([
          Text('Waiting for Google…', style: PlannerType.ui(15, color: c.tx)),
          const SizedBox(height: 12),
          Container(color: c.ln, child: bar(null, 2)),
          const SizedBox(height: 12),
          para('Finish signing in on the Google screen. Planner keeps working meanwhile.'),
        ]);
      case SyncStatus.conflict:
        final r = s.remote!;
        final ws = weekStart(dayOf(now));
        final local = PlannerSnapshot.of(data);
        final edited = data.tasks.map((t) => t.updatedAt).whereType<DateTime>().fold<DateTime?>(
            null, (a, b) => a == null || b.isAfter(a) ? b : a);
        Widget card(String title, String when, int n) => Expanded(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: c.s1, borderRadius: BorderRadius.circular(4)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: PlannerType.bricolage600(15, color: c.tx)),
                  const SizedBox(height: 6),
                  Text(when, style: PlannerType.time(size: 12, color: c.t2)),
                  const SizedBox(height: 6),
                  Text('$n ${n == 1 ? 'task' : 'tasks'} this week', style: PlannerType.ui(12, weight: 400, color: c.t3)),
                ]),
              ),
            );
        final device = r.deviceId == data.deviceId || r.deviceId == 'this-phone'
            ? 'Another device'
            : r.deviceId[0].toUpperCase() + r.deviceId.substring(1);
        body.addAll([
          Semantics(
              liveRegion: true,
              child: Text('Two versions of your plan', style: PlannerType.bricolage600(18, color: c.tx))),
          const SizedBox(height: 14),
          para('Drive has a backup from another device that is newer than this phone’s last backup. '
              'Choose which one to keep. The other is saved as a separate backup file, so nothing is lost.'),
          const SizedBox(height: 14),
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              card('This phone', 'Edited ${backupWhen(edited ?? now, now).toLowerCase()}', local.tasksInWeek(ws)),
              const SizedBox(width: 8),
              card('Drive', '$device, ${backupWhen(r.exportedAt, now).toLowerCase()}', r.tasksInWeek(ws)),
            ]),
          ),
          const SizedBox(height: 14),
          PrimaryPill(label: 'Keep this phone', height: 52, expand: true, onTap: sync.keepPhone),
          const SizedBox(height: 8),
          SecondaryPill(label: 'Use the Drive version', height: 52, expand: true, onTap: sync.useDrive),
        ]);
      case SyncStatus.synced:
      case SyncStatus.backingUp:
      case SyncStatus.restoring:
        body.addAll([
          row('Account', Text(data.driveAccount ?? '', style: PlannerType.body(size: 14, color: c.tx)), first: true),
          row('Last backup', Text(data.lastSyncAt == null ? 'Never' : backupWhen(data.lastSyncAt!, now),
              style: PlannerType.time(size: 13, color: c.tx))),
          row('Status', Text(status, style: PlannerType.body(size: 14, color: c.tx))),
          Container(
            constraints: const BoxConstraints(minHeight: 56),
            decoration: BoxDecoration(border: Border(top: line)),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text('Back up automatically', style: PlannerType.ui(14, color: c.tx)),
                  const SizedBox(height: 2),
                  Text('Every night, on Wi-Fi', style: PlannerType.ui(12, weight: 400, color: c.t3)),
                ]),
              ),
              PlannerSwitch(
                value: data.settings.autoBackup,
                label: 'Back up automatically',
                onChanged: (v) => ref
                    .read(plannerStoreProvider.notifier)
                    .setSettings(ref.read(settingsProvider).copyWith(autoBackup: v)),
              ),
            ]),
          ),
          const SizedBox(height: 22),
          if (offline) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: c.s1, borderRadius: BorderRadius.circular(12)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                PlannerIcon(PIcon.cloudOff, size: 20, color: c.t2),
                const SizedBox(width: 12),
                Expanded(
                  child: para('You’re offline. Everything is saved on this phone, '
                      'and Planner backs up as soon as you reconnect.'),
                ),
              ]),
            ),
            const SizedBox(height: 22),
            PrimaryPill(label: 'Back up when online', height: 52, expand: true, onTap: null),
            const SizedBox(height: 8),
            Center(child: TextPill(label: 'Disconnect', height: 48, onTap: sync.disconnect)),
          ] else if (s.busy) ...[
            Semantics(
              liveRegion: true,
              label: '${s.status == SyncStatus.restoring ? 'Restoring from Drive' : 'Backing up to Drive'}, '
                  '${(s.progress * 100).round()} percent',
              excludeSemantics: true,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(
                    child: Text(s.status == SyncStatus.restoring ? 'Restoring from Drive' : 'Backing up to Drive',
                        style: PlannerType.ui(14, color: c.tx)),
                  ),
                  Text('${(s.progress * 100).round()}%', style: PlannerType.time(size: 13, color: c.t2)),
                ]),
                const SizedBox(height: 10),
                bar(s.progress, 3),
              ]),
            ),
          ] else ...[
            PrimaryPill(label: 'Back up now', height: 52, expand: true, onTap: sync.backUp),
            const SizedBox(height: 8),
            SecondaryPill(label: 'Restore from Drive', height: 52, expand: true, onTap: sync.askRestore),
            const SizedBox(height: 8),
            Center(child: TextPill(label: 'Disconnect', height: 48, onTap: sync.disconnect)),
          ],
        ]);
    }

    return Stack(children: [
      ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
        children: [
          SizedBox(
            height: 44,
            // The back button's 44px target hangs 12px into the gutter.
            child: Transform.translate(
              offset: const Offset(-12, 0),
              child: Row(children: [
                PlannerIconButton(icon: PIcon.back, label: 'Back to settings', onTap: onBack, color: c.tx, size: 20),
                const SizedBox(width: 4),
                Semantics(header: true, child: Text('Google Drive', style: PlannerType.screenTitle(color: c.tx))),
              ]),
            ),
          ),
          const SizedBox(height: 22),
          ...body,
        ],
      ),
      _RestoreSheet(
        open: s.askRestore,
        onRestore: sync.restore,
        onCancel: sync.cancelRestore,
      ),
    ]);
  }
}

/// "Replace this phone's plan with the Drive backup?" [Restore] [Cancel]
class _RestoreSheet extends StatelessWidget {
  const _RestoreSheet({required this.open, required this.onRestore, required this.onCancel});
  final bool open;
  final VoidCallback onRestore, onCancel;

  @override
  Widget build(BuildContext context) {
    final c = PlannerColors.of(context);
    final d = PlannerMotion.ms(context, 460);
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !open,
        child: Stack(children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: onCancel,
              child: AnimatedOpacity(opacity: open ? 1 : 0, duration: d, child: ColoredBox(color: c.scrim)),
            ),
          ),
          AnimatedPositioned(
            duration: d,
            curve: PlannerMotion.settleCurve,
            left: 0,
            right: 0,
            bottom: open ? 0 : -360,
            child: ExcludeSemantics(
              excluding: !open,
              child: Container(
                // The page ends at the bottom nav, which already clears the home indicator.
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
                decoration: BoxDecoration(
                  color: c.s1,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(color: c.ln, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Semantics(
                    header: true,
                    child: Text('Replace this phone’s plan with the Drive backup?',
                        style: PlannerType.sheetTitle(size: 24, color: c.tx)),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Your plan on this phone will be replaced. Planner saves your current plan as a separate backup first, '
                    'so you can switch back.',
                    style: PlannerType.body(size: 14, color: c.t2),
                  ),
                  const SizedBox(height: 20),
                  PrimaryPill(label: 'Restore', height: 52, expand: true, onTap: onRestore),
                  const SizedBox(height: 8),
                  Center(child: TextPill(label: 'Cancel', height: 48, onTap: onCancel)),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// The Settings row for the Drive page.
class DriveRow extends ConsumerWidget {
  const DriveRow({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = PlannerColors.of(context);
    final s = ref.watch(syncProvider);
    final online = ref.watch(onlineProvider);
    ref.watch(clockProvider.select((t) => t.minute));
    final status = driveStatusText(s, ref.watch(plannerStoreProvider), online: online, now: DateTime.now());
    return Pressable(
      onTap: onTap,
      label: 'Google Drive, $status',
      radius: 4,
      pressedScale: 0.99,
      excludeChildSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: 60),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: c.ln))),
        child: Row(children: [
          PlannerIcon(!online && s.connected ? PIcon.cloudOff : PIcon.cloud, size: 20, color: c.t2),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('Google Drive', style: PlannerType.ui(14, color: c.tx)),
              const SizedBox(height: 2),
              Text(status, style: PlannerType.ui(12, weight: 400, color: c.t3)),
            ]),
          ),
          PlannerIcon(PIcon.chev, size: 16, color: c.t3, stroke: 1.6),
        ]),
      ),
    );
  }
}
