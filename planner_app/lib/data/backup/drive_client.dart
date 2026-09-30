import 'dart:async';

import '../snapshot.dart';

/// The single backup Planner keeps in the Drive app-data folder.
const kBackupName = 'planner-backup.json';

/// A kept loser after a conflict, or the plan saved before a restore.
String keptBackupName(DateTime at) {
  String two(int v) => v.toString().padLeft(2, '0');
  return 'planner-backup-${at.year}${two(at.month)}${two(at.day)}-${two(at.hour)}${two(at.minute)}${two(at.second)}.json';
}

/// A readable failure the Drive page can show as-is.
class DriveException implements Exception {
  const DriveException(this.message);
  final String message;
  @override
  String toString() => 'DriveException: $message';
}

/// Google Drive, `drive.appdata` scope only (README 6.11): Planner sees just
/// the files it creates. Behind an interface so every state can be built
/// and tested before OAuth client ids exist.
abstract class DriveClient {
  /// Interactive sign-in. Returns the account email, or null if cancelled.
  Future<String?> signIn();

  /// A session restored silently at launch, if any.
  Future<String?> restoreSession();
  Future<void> signOut();

  /// The main backup, or null when Drive has none yet.
  Future<PlannerSnapshot?> readBackup();

  /// Writes [s] as [name]; [onProgress] reports 0..1.
  Future<void> write(PlannerSnapshot s, {String name = kBackupName, void Function(double p)? onProgress});
}

/// An in-memory Drive with realistic timing, used until the real client is
/// configured (and in tests, with [delay] zero). Debug tools can plant a
/// newer backup "from another device" to produce a conflict.
class FakeDriveClient implements DriveClient {
  FakeDriveClient({this.delay = const Duration(milliseconds: 140), this.account = 'you@gmail.com'});

  /// Time per 10% of an upload.
  final Duration delay;
  final String account;
  bool _signedIn = false;
  PlannerSnapshot? remote;
  final kept = <String, PlannerSnapshot>{};

  /// Simulates the user backing out of the Google screen.
  bool cancelNextSignIn = false;

  @override
  Future<String?> signIn() async {
    await Future<void>.delayed(delay * 11);
    if (cancelNextSignIn) {
      cancelNextSignIn = false;
      return null;
    }
    _signedIn = true;
    return account;
  }

  @override
  Future<String?> restoreSession() async => _signedIn ? account : null;

  @override
  Future<void> signOut() async => _signedIn = false;

  @override
  Future<PlannerSnapshot?> readBackup() async {
    await Future<void>.delayed(delay);
    return remote;
  }

  @override
  Future<void> write(PlannerSnapshot s, {String name = kBackupName, void Function(double p)? onProgress}) async {
    for (var i = 1; i <= 10; i++) {
      await Future<void>.delayed(delay);
      onProgress?.call(i / 10);
    }
    if (name == kBackupName) {
      remote = s;
    } else {
      kept[name] = s;
    }
  }
}
