import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/app/journey.dart';

/// README 11 acceptance on a real device, in real time (about a minute).
/// The journey runs on an in-memory store with a fake clock, so the data on
/// the device is never touched. Run with:
///   flutter test integration_test -d macos
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('acceptance: onboard → voice → Move Flutter → done early → missed → weekend → review',
      acceptanceJourney);
}
