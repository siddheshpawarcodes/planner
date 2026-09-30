import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:planner_app/app/dev/scenarios.dart';
import 'package:planner_app/data/backup/drive_client.dart';
import 'package:planner_app/data/backup/google_drive_client.dart';
import 'package:planner_app/data/snapshot.dart';

class FakeAuth implements DriveAuth {
  String? next = 'tok1';
  bool cancel = false;
  final forgotten = <String>[], revoked = <String>[];
  @override
  Future<String?> token({required bool interactive}) async => cancel ? null : next;
  @override
  Future<void> forget(String token) async {
    forgotten.add(token);
    next = 'tok2';
  }

  @override
  Future<void> revoke(String token) async => revoked.add(token);
}

/// A tiny Drive v3 appDataFolder in memory.
class FakeDrive {
  final files = <String, (String name, String body)>{};
  final seenTokens = <String?>[];
  var n = 0;
  bool expireNext = false;

  MockClient get client => MockClient((r) async {
        seenTokens.add(r.headers['Authorization']);
        if (expireNext) {
          expireNext = false;
          return http.Response('{"error":{"code":401,"message":"expired"}}', 401,
              headers: {'content-type': 'application/json'});
        }
        final u = r.url;
        json(Object o) => http.Response(jsonEncode(o), 200, headers: {'content-type': 'application/json'});
        if (u.host == 'www.googleapis.com' && u.path == '/oauth2/v3/userinfo') return json({'email': 'siddhesh@example.com'});
        if (u.path == '/drive/v3/files' && r.method == 'GET') {
          expect(u.queryParameters['spaces'], 'appDataFolder');
          final m = RegExp(r"name = '([^']+)'").firstMatch(u.queryParameters['q']!)!;
          return json({
            'files': [
              for (final e in files.entries)
                if (e.value.$1 == m[1]) {'id': e.key, 'name': e.value.$1}
            ]
          });
        }
        if (u.path.startsWith('/drive/v3/files/') && u.queryParameters['alt'] == 'media') {
          return http.Response(files[u.pathSegments.last]!.$2, 200, headers: {'content-type': 'application/json'});
        }
        if (u.path.startsWith('/upload/drive/v3/files')) {
          // multipart/related: JSON metadata, then the file (base64).
          final body = r is http.Request ? r.body : '';
          final boundary = RegExp(r'boundary="?([^";]+)"?').firstMatch(r.headers['content-type']!)![1]!;
          final parts = body.split('--$boundary').where((p) => p.trim().isNotEmpty && p.trim() != '--').toList();
          String payload(String part) => part.split(RegExp(r'\r?\n\r?\n')).skip(1).join('\n\n').trim();
          final meta = RegExp(r'"name"\s*:\s*"([^"]+)"').firstMatch(payload(parts[0]));
          final raw = payload(parts[1]);
          final content = parts[1].toLowerCase().contains('base64') ? utf8.decode(base64.decode(raw)) : raw;
          if (r.method == 'POST') {
            expect(payload(parts[0]), contains('"parents":["appDataFolder"]'));
            final id = 'f${++n}';
            files[id] = (meta![1]!, content);
            return json({'id': id});
          }
          final id = u.pathSegments.last;
          files[id] = (files[id]!.$1, content);
          return json({'id': id});
        }
        return http.Response('not found ${r.method} $u', 404);
      });
}

void main() {
  final snap = PlannerSnapshot.of(buildScenario(Scenario.week, now: DateTime(2026, 9, 28)).data,
      at: DateTime(2026, 10, 1, 21, 14));

  test('sign-in returns the account email; a cancel returns null', () async {
    final auth = FakeAuth(), d = FakeDrive();
    final c = GoogleDriveClient(auth: auth, http: d.client);
    expect(await c.signIn(), 'siddhesh@example.com');
    auth.cancel = true;
    expect(await c.signIn(), isNull);
  });

  test('first backup creates planner-backup.json in appDataFolder, later ones update it', () async {
    final d = FakeDrive();
    final c = GoogleDriveClient(auth: FakeAuth(), http: d.client);
    expect(await c.readBackup(), isNull);
    final progress = <double>[];
    await c.write(snap, onProgress: progress.add);
    expect(d.files.values.single.$1, kBackupName);
    expect(progress.last, 1);
    await c.write(snap);
    expect(d.files.length, 1, reason: 'updated in place');
    final back = await c.readBackup();
    expect(back!.tasks.length, snap.tasks.length);
    expect(back.exportedAt, snap.exportedAt);
    expect(d.seenTokens.every((t) => t == 'Bearer tok1'), isTrue);
  });

  test('kept versions are separate files', () async {
    final d = FakeDrive();
    final c = GoogleDriveClient(auth: FakeAuth(), http: d.client);
    await c.write(snap);
    await c.write(snap, name: keptBackupName(DateTime(2026, 10, 1, 21, 14, 5)));
    expect(d.files.values.map((f) => f.$1).toSet(), {kBackupName, 'planner-backup-20261001-211405.json'});
  });

  test('an expired token is dropped and the call retried once', () async {
    final auth = FakeAuth(), d = FakeDrive()..expireNext = true;
    final c = GoogleDriveClient(auth: auth, http: d.client);
    expect(await c.readBackup(), isNull);
    expect(auth.forgotten, ['tok1']);
    expect(d.seenTokens.last, 'Bearer tok2');
  });

  test('no token: a clear message instead of a crash; disconnect revokes', () async {
    final auth = FakeAuth()..cancel = true;
    final c = GoogleDriveClient(auth: auth, http: FakeDrive().client);
    expect(c.readBackup(), throwsA(isA<DriveException>()));
    auth.cancel = false;
    await c.signOut();
    expect(auth.revoked, ['tok1']);
  });
}
