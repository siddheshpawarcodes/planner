import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planner_app/app/dev/scenarios.dart';
import 'package:planner_app/app/state/note.dart';
import 'package:planner_app/app/state/store.dart';
import 'package:planner_app/app/state/ui_state.dart';
import 'package:planner_app/data/backup/drive_client.dart';
import 'package:planner_app/data/backup/sync.dart';
import 'package:planner_app/data/planner_data.dart';
import 'package:planner_app/data/repository.dart';
import 'package:planner_app/data/snapshot.dart';

class Rig {
  Rig(PlannerData data) {
    repo = MemoryPlannerRepository(data);
    c = ProviderContainer(overrides: [
      repositoryProvider.overrideWithValue(repo),
      initialDataProvider.overrideWithValue(data),
      driveClientProvider.overrideWithValue(drive),
    ]);
  }
  final drive = FakeDriveClient(delay: Duration.zero);
  late final MemoryPlannerRepository repo;
  late final ProviderContainer c;
  SyncController get sync => c.read(syncProvider.notifier);
  SyncState get state => c.read(syncProvider);
  PlannerData get data => c.read(plannerStoreProvider);
  String? get note => c.read(noteProvider)?.text;
}

PlannerData week({bool changed = true, DateTime? lastSync}) => buildScenario(Scenario.week, now: DateTime(2026, 9, 28))
    .data
    .copyWith(changedSinceSync: changed, lastSyncAt: lastSync);

void main() {
  test('connect with an empty Drive backs up straight away', () async {
    final r = Rig(week());
    final seen = <SyncStatus>[];
    r.c.listen(syncProvider, (_, s) => seen.add(s.status), fireImmediately: true);
    await r.sync.connect();
    expect(seen, containsAllInOrder([SyncStatus.off, SyncStatus.connecting, SyncStatus.synced, SyncStatus.backingUp, SyncStatus.synced]));
    expect(r.data.driveAccount, 'you@gmail.com');
    expect(r.data.changedSinceSync, isFalse);
    expect(r.data.lastSyncAt, isNotNull);
    expect(r.drive.remote!.tasks.length, r.data.tasks.length);
    expect(r.repo.data.driveAccount, 'you@gmail.com', reason: 'the connection is saved');
  });

  test('a cancelled Google sign-in leaves Drive off', () async {
    final r = Rig(week());
    r.drive.cancelNextSignIn = true;
    await r.sync.connect();
    expect(r.state.status, SyncStatus.off);
    expect(r.note, 'Google Drive isn’t connected. Everything stays on this phone.');
  });

  group('conflict: Drive newer than the last sync, and this phone changed', () {
    Future<Rig> conflicted() async {
      final r = Rig(week(lastSync: DateTime(2026, 9, 30, 8)).copyWith(driveAccount: 'you@gmail.com'));
      r.drive.remote = PlannerSnapshot.of(r.data.copyWith(tasks: r.data.tasks.sublist(2), deviceId: 'tablet'),
          at: DateTime(2026, 9, 30, 22, 40));
      await r.sync.backUp();
      expect(r.state.status, SyncStatus.conflict);
      return r;
    }

    test('Keep this phone: the Drive copy is kept as a separate file', () async {
      final r = await conflicted();
      final phone = r.data.tasks.length;
      await r.sync.keepPhone();
      expect(r.state.status, SyncStatus.synced);
      expect(r.drive.kept.values.single.deviceId, 'tablet');
      expect(r.drive.remote!.tasks.length, phone);
      expect(r.note, 'Kept this phone. The Drive copy was saved as a separate backup.');
    });

    test('Use the Drive version: this phone is saved first, then replaced', () async {
      final r = await conflicted();
      final phone = r.data.tasks.length;
      await r.sync.useDrive();
      expect(r.drive.kept.values.single.tasks.length, phone);
      expect(r.data.tasks.length, phone - 2);
      expect(r.data.changedSinceSync, isFalse);
      expect(r.data.driveAccount, 'you@gmail.com', reason: 'still connected');
      expect(r.note, 'Using the Drive version. This phone’s copy was saved first.');
    });
  });

  test('Drive newer and nothing new here: take Drive’s version, no question', () async {
    final r = Rig(week(changed: false, lastSync: DateTime(2026, 9, 30, 8)).copyWith(driveAccount: 'you@gmail.com'));
    r.drive.remote = PlannerSnapshot.of(r.data.copyWith(tasks: r.data.tasks.sublist(1)), at: DateTime(2026, 9, 30, 20));
    await r.sync.backUp();
    expect(r.state.status, SyncStatus.synced);
    expect(r.data.tasks.length, r.drive.remote!.tasks.length);
    expect(r.note, 'Updated from your Drive backup.');
  });

  test('restore saves this phone’s plan first', () async {
    final r = Rig(week().copyWith(driveAccount: 'you@gmail.com'));
    r.drive.remote = PlannerSnapshot.of(r.data.copyWith(tasks: const []), at: DateTime(2026, 9, 29));
    final before = r.data.tasks.length;
    r.sync.askRestore();
    expect(r.state.askRestore, isTrue);
    await r.sync.restore();
    expect(r.state.askRestore, isFalse);
    expect(r.drive.kept.values.single.tasks.length, before);
    expect(r.data.tasks, isEmpty);
    expect(r.note, 'Restored from your Drive backup. The previous plan was saved first.');
  });

  test('offline: nothing is sent, and the status says why', () async {
    final r = Rig(week().copyWith(driveAccount: 'you@gmail.com'));
    r.c.read(onlineProvider.notifier).set(false);
    await r.sync.backUp();
    expect(r.drive.remote, isNull);
    expect(driveStatusText(r.state, r.data, online: false, now: DateTime(2026, 9, 30)), 'Offline, waiting to back up');
  });

  test('automatic backup: connected, on Wi-Fi, with changes, at most every 20h', () async {
    final r = Rig(week(lastSync: DateTime(2026, 9, 30, 8)).copyWith(driveAccount: 'you@gmail.com'));
    await r.sync.autoBackUpIfDue(wifi: false, now: DateTime(2026, 10, 1, 9));
    expect(r.drive.remote, isNull, reason: 'not on Wi-Fi');
    await r.sync.autoBackUpIfDue(wifi: true, now: DateTime(2026, 9, 30, 20));
    expect(r.drive.remote, isNull, reason: 'backed up 12h ago');
    await r.sync.autoBackUpIfDue(wifi: true, now: DateTime(2026, 10, 1, 9));
    expect(r.drive.remote, isNotNull);
  });

  test('disconnect keeps everything on the phone', () async {
    final r = Rig(week().copyWith(driveAccount: 'you@gmail.com'));
    await r.sync.disconnect();
    expect(r.state.status, SyncStatus.off);
    expect(r.data.driveAccount, isNull);
    expect(r.data.tasks, isNotEmpty);
    expect(r.note, 'Disconnected. Everything stays on this phone.');
  });

  test('status copy', () {
    final now = DateTime(2026, 10, 1, 21, 30);
    final d = const PlannerData();
    expect(driveStatusText(const SyncState(), d, online: true, now: now), 'Not connected');
    expect(driveStatusText(const SyncState(status: SyncStatus.synced), d.copyWith(lastSyncAt: DateTime(2026, 10, 1, 19, 2)),
        online: true, now: now), 'Backed up today 19:02');
    expect(backupWhen(DateTime(2026, 9, 30, 22, 40), now), 'Yesterday 22:40');
    expect(backupWhen(DateTime(2026, 9, 28, 9), now), '28 Sep');
    expect(backupWhen(DateTime(2026, 10, 1, 21, 29), now), 'Just now');
    expect(driveStatusText(const SyncState(status: SyncStatus.conflict), d, online: false, now: now), 'Needs a decision');
    expect(keptBackupName(DateTime(2026, 10, 1, 21, 14, 5)), 'planner-backup-20261001-211405.json');
  });
}
