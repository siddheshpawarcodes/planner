import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/state/note.dart';
import '../../app/state/store.dart';
import '../../app/state/ui_state.dart';
import '../../domain/time.dart';
import '../planner_data.dart';
import '../snapshot.dart';
import 'drive_client.dart';

enum SyncStatus { off, connecting, synced, backingUp, restoring, conflict }

/// `syncProvider`: the Drive state machine (README 6.11). Offline is not a
/// state of its own; it is how a connected state reads while [onlineProvider]
/// is false.
class SyncState {
  const SyncState({this.status = SyncStatus.off, this.progress = 0, this.remote, this.askRestore = false});
  final SyncStatus status;

  /// Backing up / restoring, 0..1.
  final double progress;

  /// The Drive version while a conflict waits for a decision.
  final PlannerSnapshot? remote;

  /// The restore confirmation sheet is showing.
  final bool askRestore;

  bool get connected => status != SyncStatus.off && status != SyncStatus.connecting;
  bool get busy => status == SyncStatus.backingUp || status == SyncStatus.restoring;

  SyncState copyWith({SyncStatus? status, double? progress, PlannerSnapshot? remote, bool? askRestore}) => SyncState(
        status: status ?? this.status,
        progress: progress ?? this.progress,
        remote: remote ?? this.remote,
        askRestore: askRestore ?? this.askRestore,
      );
}

/// Conflict = the Drive backup is newer than this phone's last sync *and*
/// this phone has changed since. There is no silent merge.
bool isConflict(PlannerSnapshot? remote, PlannerData local) =>
    remote != null &&
    local.changedSinceSync &&
    (local.lastSyncAt == null || remote.exportedAt.isAfter(local.lastSyncAt!));

/// Drive is newer and this phone has nothing new: take Drive's version.
bool isBehind(PlannerSnapshot? remote, PlannerData local) =>
    remote != null &&
    !local.changedSinceSync &&
    local.lastSyncAt != null &&
    remote.exportedAt.isAfter(local.lastSyncAt!);

/// "Today 19:02", "Yesterday 22:40", "28 Sep".
String backupWhen(DateTime at, DateTime now) {
  final d = dayOf(now) - dayOf(at);
  final t = fmt(at.hour * 60 + at.minute);
  if (d == 0) return now.difference(at).inMinutes < 2 ? 'Just now' : 'Today $t';
  if (d == 1) return 'Yesterday $t';
  return '${at.day} ${monthShortNames[at.month - 1]}';
}

/// The Drive row's status line.
String driveStatusText(SyncState s, PlannerData d, {required bool online, required DateTime now}) {
  if (!online && s.connected && s.status != SyncStatus.conflict) return 'Offline, waiting to back up';
  return switch (s.status) {
    SyncStatus.off => 'Not connected',
    SyncStatus.connecting => 'Connecting…',
    SyncStatus.backingUp => 'Backing up…',
    SyncStatus.restoring => 'Restoring…',
    SyncStatus.conflict => 'Needs a decision',
    SyncStatus.synced =>
      d.lastSyncAt == null ? 'Connected' : 'Backed up ${backupWhen(d.lastSyncAt!, now).toLowerCase()}',
  };
}

/// Overridden in `main` once the real Google client exists; until then the
/// in-memory stand-in behaves like Drive.
final driveClientProvider = Provider<DriveClient>((ref) => FakeDriveClient());

final syncProvider = NotifierProvider<SyncController, SyncState>(SyncController.new);

class SyncController extends Notifier<SyncState> {
  DriveClient get _drive => ref.read(driveClientProvider);
  PlannerStore get _store => ref.read(plannerStoreProvider.notifier);
  PlannerData get _data => ref.read(plannerStoreProvider);
  NoteController get _note => ref.read(noteProvider.notifier);
  bool get _online => ref.read(onlineProvider);

  @override
  SyncState build() => SyncState(
      status: ref.read(plannerStoreProvider).driveAccount == null ? SyncStatus.off : SyncStatus.synced);

  /// Connect Google Drive: sign in, then compare with any existing backup.
  Future<void> connect() async {
    if (state.status != SyncStatus.off) return;
    state = const SyncState(status: SyncStatus.connecting);
    String? account;
    String? why;
    try {
      account = await _drive.signIn();
    } on DriveException catch (e) {
      why = e.message;
    } catch (_) {}
    if (account == null) {
      state = const SyncState();
      _note.say(why ?? 'Google Drive isn’t connected. Everything stays on this phone.');
      return;
    }
    await _store.setMeta(driveAccount: account);
    state = const SyncState(status: SyncStatus.synced);
    await backUp(announce: false);
  }

  /// Back up now (or automatically): checks Drive first, so a newer backup
  /// from another device is never overwritten.
  Future<void> backUp({bool announce = true}) async {
    if (!state.connected || state.busy || !_online) return;
    PlannerSnapshot? remote;
    try {
      remote = await _drive.readBackup();
    } on DriveException catch (e) {
      if (announce) _note.say(e.message);
      return;
    } catch (_) {
      if (announce) _note.say('Couldn’t reach Google Drive. Planner will try again later.');
      return;
    }
    if (isConflict(remote, _data)) {
      state = SyncState(status: SyncStatus.conflict, remote: remote);
      return;
    }
    if (isBehind(remote, _data)) {
      await _apply(remote!);
      _note.say('Updated from your Drive backup.');
      return;
    }
    await _upload(announce ? 'Backed up to Google Drive.' : null);
  }

  Future<void> _upload(String? done) async {
    final before = _data;
    final at = DateTime.now();
    state = state.copyWith(status: SyncStatus.backingUp, progress: 0);
    try {
      await _drive.write(PlannerSnapshot.of(before, at: at),
          onProgress: (p) => state = state.copyWith(progress: p));
    } catch (e) {
      state = const SyncState(status: SyncStatus.synced);
      _note.say(e is DriveException ? e.message : 'Backup didn’t finish. Everything is still on this phone.');
      return;
    }
    // Edits made during the upload still count as changes.
    await _store.setMeta(lastSyncAt: at, changedSinceSync: !identical(_data, before) && _data.changedSinceSync);
    state = const SyncState(status: SyncStatus.synced);
    if (done != null) _note.say(done);
  }

  /// Replaces this phone's plan with [remote] (already confirmed).
  Future<void> _apply(PlannerSnapshot remote) async {
    final next = remote.applyTo(_data).copyWith(lastSyncAt: remote.exportedAt, changedSinceSync: false);
    await _store.replaceAll(next);
    state = const SyncState(status: SyncStatus.synced);
  }

  void askRestore() => state = state.copyWith(askRestore: true);
  void cancelRestore() => state = state.copyWith(askRestore: false);

  /// Restore from Drive: this phone's plan is saved as a separate backup
  /// first, so you can switch back.
  Future<void> restore() async {
    state = state.copyWith(askRestore: false);
    if (!state.connected || state.busy || !_online) return;
    state = state.copyWith(status: SyncStatus.restoring, progress: 0);
    try {
      final remote = await _drive.readBackup();
      if (remote == null) {
        state = const SyncState(status: SyncStatus.synced);
        _note.say('There’s no backup on Drive yet.');
        return;
      }
      await _drive.write(PlannerSnapshot.of(_data),
          name: keptBackupName(DateTime.now()), onProgress: (p) => state = state.copyWith(progress: p * 0.8));
      await _apply(remote);
      _note.say('Restored from your Drive backup. The previous plan was saved first.');
    } catch (e) {
      state = const SyncState(status: SyncStatus.synced);
      _note.say(e is DriveException ? e.message : 'Restore didn’t finish. Nothing was changed.');
    }
  }

  /// Conflict › Keep this phone: the Drive copy is kept as a separate file.
  Future<void> keepPhone() async {
    final remote = state.remote;
    if (remote == null) return;
    try {
      await _drive.write(remote, name: keptBackupName(remote.exportedAt));
    } catch (_) {
      _note.say('Couldn’t reach Google Drive. Nothing was changed.');
      return;
    }
    state = const SyncState(status: SyncStatus.synced);
    await _upload('Kept this phone. The Drive copy was saved as a separate backup.');
  }

  /// Conflict › Use the Drive version: this phone's copy is saved first.
  Future<void> useDrive() async {
    final remote = state.remote;
    if (remote == null) return;
    try {
      await _drive.write(PlannerSnapshot.of(_data), name: keptBackupName(DateTime.now()));
    } catch (_) {
      _note.say('Couldn’t reach Google Drive. Nothing was changed.');
      return;
    }
    await _apply(remote);
    _note.say('Using the Drive version. This phone’s copy was saved first.');
  }

  /// Debug: plants a newer Drive backup "from the tablet" (two tasks fewer,
  /// yesterday 22:40) in the stand-in client, then syncs into the conflict.
  Future<void> debugConflict() async {
    final fake = _drive;
    if (fake is! FakeDriveClient) return;
    final now = DateTime.now();
    final y = DateTime(now.year, now.month, now.day - 1, 22, 40);
    final d = _data;
    final tasks = d.tasks.where((t) => !t.deleted).toList();
    fake.remote = PlannerSnapshot.of(
      d.copyWith(tasks: tasks.length > 2 ? tasks.sublist(0, tasks.length - 2) : tasks, deviceId: 'tablet'),
      at: y,
    );
    if (state.status == SyncStatus.off) {
      await _store.setMeta(driveAccount: fake.account);
      state = const SyncState(status: SyncStatus.synced);
    }
    await _store.setMeta(lastSyncAt: y.subtract(const Duration(days: 1)), changedSinceSync: true);
    await backUp(announce: false);
  }

  Future<void> disconnect() async {
    try {
      await _drive.signOut();
    } catch (_) {}
    await _store.setMeta(driveAccount: null);
    state = const SyncState();
    _note.say('Disconnected. Everything stays on this phone.');
  }

  /// Back up automatically: nightly-ish, on Wi-Fi, only with changes. Runs
  /// when the app opens, resumes or reconnects (there is no background job).
  Future<void> autoBackUpIfDue({required bool wifi, DateTime? now}) async {
    final d = _data;
    final t = now ?? DateTime.now();
    if (state.status != SyncStatus.synced || !d.settings.autoBackup || !wifi || !_online) return;
    if (!d.changedSinceSync) return;
    if (d.lastSyncAt != null && t.difference(d.lastSyncAt!) < const Duration(hours: 20)) return;
    await backUp(announce: false);
  }
}
