import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/dev/scenarios.dart';
import 'app/state/clock.dart';
import 'app/state/store.dart';
import 'data/backup/drive_client.dart';
import 'data/backup/google_drive_client.dart';
import 'data/backup/sync.dart';
import 'data/database.dart';
import 'data/repository.dart';
import 'domain/time.dart';
import 'features/notifications/notification_service.dart';
import 'features/offline/network.dart';
import 'features/voice/porcupine_engine.dart';
import 'features/voice/wake_word.dart';

/// Debug: `--dart-define=PLANNER_SCENARIO=wed` starts at a journey step.
const _scenario = String.fromEnvironment('PLANNER_SCENARIO');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repo = DriftPlannerRepository(PlannerDatabase());
  var data = await repo.load();
  DateTime? pinned;

  if (kDebugMode && _scenario.isNotEmpty) {
    final k = Scenario.values.where((s) => s.name == _scenario).firstOrNull;
    if (k != null) {
      final s = buildScenario(k);
      data = s.data.copyWith(settings: data.settings);
      await repo.replaceAll(data);
      pinned = s.clock;
    }
  }
  if (data.installedDay == null) {
    // First launch: the router opens onboarding, which sets the routine.
    data = data.copyWith(installedDay: dayOf(DateTime.now()));
    await repo.putMeta(metaOf(data));
  }

  final wake = await PorcupineWakeWordEngine.create();
  // Google Drive (drive.appdata): Android has its OAuth client; iOS waits
  // for one, so debug builds there keep the stand-in to exercise the UI.
  final DriveClient drive = defaultTargetPlatform == TargetPlatform.android
      ? GoogleDriveClient(auth: GoogleSignInAuth())
      : kDebugMode
          ? FakeDriveClient()
          : const UnavailableDriveClient();

  final container = ProviderContainer(overrides: [
    repositoryProvider.overrideWithValue(repo),
    initialDataProvider.overrideWithValue(data),
    notificationServiceProvider.overrideWithValue(LocalNotifications()),
    connectivityProvider.overrideWithValue(Connectivity()),
    wakeWordEngineProvider.overrideWithValue(wake),
    driveClientProvider.overrideWithValue(drive),
  ]);
  if (pinned != null) container.read(clockProvider.notifier).pin(pinned);
  runApp(UncontrolledProviderScope(container: container, child: const PlannerApp()));
}
