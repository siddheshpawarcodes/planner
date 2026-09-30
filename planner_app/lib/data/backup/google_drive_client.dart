import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

import '../snapshot.dart';
import 'drive_client.dart';

/// Only the app data folder: Planner sees just the files it creates
/// (README 6.11), plus the email for the Account row.
const kDriveScopes = [drive.DriveApi.driveAppdataScope, 'https://www.googleapis.com/auth/userinfo.email'];

/// Access tokens for [kDriveScopes]. Behind an interface so the Drive logic
/// can be tested without Google Play services.
abstract class DriveAuth {
  /// A current token; with [interactive] the account picker and consent may
  /// show. Null when the user cancels or (silently) has not granted access.
  Future<String?> token({required bool interactive});

  /// Drops a token that Google rejected, so the next call fetches a new one.
  Future<void> forget(String token);

  /// Revokes Planner's access entirely.
  Future<void> revoke(String token);
}

/// `google_sign_in` 7 on Android: authorization only (Identity
/// AuthorizationClient), which needs the Android OAuth client registered
/// for the package and signing SHA-1 but no web client id.
class GoogleSignInAuth implements DriveAuth {
  GoogleSignInAuth({http.Client? http}) : _http = http ?? _httpClient();
  final http.Client _http;
  Future<void>? _init;

  static http.Client _httpClient() => http.Client();

  Future<void> _ready() => _init ??= GoogleSignIn.instance.initialize();

  @override
  Future<String?> token({required bool interactive}) async {
    await _ready();
    final c = GoogleSignIn.instance.authorizationClient;
    try {
      final a = interactive ? await c.authorizeScopes(kDriveScopes) : await c.authorizationForScopes(kDriveScopes);
      return a?.accessToken;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled || e.code == GoogleSignInExceptionCode.interrupted) {
        return null;
      }
      if (kDebugMode) debugPrint('[drive] sign-in ${e.code}: ${e.description}');
      throw DriveException(e.code == GoogleSignInExceptionCode.clientConfigurationError ||
              e.code == GoogleSignInExceptionCode.providerConfigurationError
          ? 'Google sign-in isn’t set up for this build of Planner.'
          : 'Google sign-in didn’t finish. Nothing was changed.');
    }
  }

  @override
  Future<void> forget(String token) async {
    await _ready();
    await GoogleSignIn.instance.authorizationClient.clearAuthorizationToken(accessToken: token);
  }

  @override
  Future<void> revoke(String token) async {
    try {
      await _http.post(Uri.parse('https://oauth2.googleapis.com/revoke'), body: {'token': token});
    } catch (_) {
      // Offline: the local token is still dropped below.
    }
    await forget(token);
  }
}

class _Bearer extends http.BaseClient {
  _Bearer(this._inner, this._token);
  final http.Client _inner;
  final String _token;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $_token';
    return _inner.send(request);
  }
}

/// Google Drive v3, `appDataFolder` space (README 6.11): one
/// `planner-backup.json`, plus `planner-backup-<timestamp>.json` files for
/// kept versions.
class GoogleDriveClient implements DriveClient {
  GoogleDriveClient({required this.auth, http.Client? http}) : _http = http ?? _default();
  final DriveAuth auth;
  final http.Client _http;

  static http.Client _default() => http.Client();

  /// Runs [f] with a fresh token, retrying once if Google rejects it.
  Future<T> _call<T>(Future<T> Function(drive.DriveApi api, http.Client authed) f) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final token = await auth.token(interactive: false);
      if (token == null) throw const DriveException('Reconnect Google Drive to keep backing up.');
      final authed = _Bearer(_http, token);
      try {
        return await f(drive.DriveApi(authed), authed);
      } on drive.DetailedApiRequestError catch (e) {
        if (e.status == 401 && attempt == 0) {
          await auth.forget(token);
          continue;
        }
        if (kDebugMode) debugPrint('[drive] ${e.status} ${e.message}');
        throw DriveException(e.status == 403
            ? 'Google Drive refused the request. Check that the Drive API is enabled for Planner.'
            : 'Google Drive had a problem (${e.status}). Everything is still on this phone.');
      } on drive.ApiRequestError catch (e) {
        if (kDebugMode) debugPrint('[drive] ${e.message}');
        throw const DriveException('Google Drive sent something unexpected. Everything is still on this phone.');
      } on FormatException {
        throw const DriveException('The Drive backup couldn’t be read. Nothing was changed.');
      }
    }
    throw const DriveException('Reconnect Google Drive to keep backing up.');
  }

  Future<String?> _email(http.Client authed) async {
    final r = await authed.get(Uri.parse('https://www.googleapis.com/oauth2/v3/userinfo'));
    if (r.statusCode != 200) return null;
    return (jsonDecode(r.body) as Map)['email'] as String?;
  }

  @override
  Future<String?> signIn() async {
    final token = await auth.token(interactive: true);
    if (token == null) return null;
    return await _email(_Bearer(_http, token)) ?? 'Google account';
  }

  @override
  Future<String?> restoreSession() async {
    final token = await auth.token(interactive: false);
    if (token == null) return null;
    return _email(_Bearer(_http, token));
  }

  @override
  Future<void> signOut() async {
    final token = await auth.token(interactive: false);
    if (token != null) await auth.revoke(token);
  }

  Future<drive.File?> _find(drive.DriveApi api, String name) async {
    final list = await api.files.list(
      spaces: 'appDataFolder',
      q: "name = '$name' and trashed = false",
      $fields: 'files(id,name,modifiedTime)',
      orderBy: 'modifiedTime desc',
      pageSize: 1,
    );
    final files = list.files ?? const [];
    return files.isEmpty ? null : files.first;
  }

  @override
  Future<PlannerSnapshot?> readBackup() => _call((api, _) async {
        final f = await _find(api, kBackupName);
        if (f?.id == null) return null;
        final media = await api.files.get(f!.id!, downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
        final text = await utf8.decodeStream(media.stream);
        return PlannerSnapshot.decode(text);
      });

  @override
  Future<void> write(PlannerSnapshot s, {String name = kBackupName, void Function(double p)? onProgress}) =>
      _call((api, _) async {
        final bytes = utf8.encode(s.encode());
        var sent = 0;
        // Progress follows the bytes the upload actually reads.
        final stream = Stream<List<int>>.fromIterable([
          for (var i = 0; i < bytes.length; i += 4096) bytes.sublist(i, i + 4096 > bytes.length ? bytes.length : i + 4096)
        ]).map((chunk) {
          sent += chunk.length;
          onProgress?.call(0.9 * sent / bytes.length);
          return chunk;
        });
        final media = drive.Media(stream, bytes.length, contentType: 'application/json');
        final existing = name == kBackupName ? await _find(api, name) : null;
        if (existing?.id != null) {
          await api.files.update(drive.File(), existing!.id!, uploadMedia: media);
        } else {
          await api.files.create(drive.File(name: name, parents: ['appDataFolder']), uploadMedia: media);
        }
        onProgress?.call(1);
      });
}

/// Where Drive backup can't run yet (iOS until its OAuth client exists):
/// connecting explains that instead of pretending.
class UnavailableDriveClient implements DriveClient {
  const UnavailableDriveClient();
  static const _why = 'Google Drive backup isn’t available on this device yet. Everything stays on this phone.';
  @override
  Future<String?> signIn() => Future.error(const DriveException(_why));
  @override
  Future<String?> restoreSession() async => null;
  @override
  Future<void> signOut() async {}
  @override
  Future<PlannerSnapshot?> readBackup() => Future.error(const DriveException(_why));
  @override
  Future<void> write(PlannerSnapshot s, {String name = kBackupName, void Function(double p)? onProgress}) =>
      Future.error(const DriveException(_why));
}
