import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planner_app/features/voice/porcupine_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('without an AccessKey the wake phrase stays off, and says why', () async {
    final e = await PorcupineWakeWordEngine.create(accessKey: '');
    expect(e.available, isFalse);
    expect(e.unavailableReason, 'No Picovoice AccessKey in this build.');
  });

  test('without the keyword model the wake phrase stays off', () async {
    final e = await PorcupineWakeWordEngine.create(accessKey: 'key');
    expect(e.available, isFalse);
    expect(e.unavailableReason, contains('assets/wake/hey_planner_android.ppn'));
  });

  test('one keyword model per platform', () {
    expect(keywordAssetFor(TargetPlatform.android), 'assets/wake/hey_planner_android.ppn');
    expect(keywordAssetFor(TargetPlatform.iOS), 'assets/wake/hey_planner_ios.ppn');
  });
}
