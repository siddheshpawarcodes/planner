import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planner_app/features/voice/vosk_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const wake = MethodChannel('planner/wake');
  const perms = MethodChannel('flutter.baseflow.com/permissions/methods');

  tearDown(() {
    messenger.setMockMethodCallHandler(wake, null);
    messenger.setMockMethodCallHandler(perms, null);
    messenger.setMockStreamHandler(const EventChannel('planner/wake/events'), null);
  });

  test('without the Android side the wake phrase stays off, and says why', () async {
    final e = await VoskWakeWordEngine.create();
    expect(e.available, isFalse);
    expect(e.unavailableReason, 'No wake-word engine in this build.');
  });

  test('a build without the model says how to add it', () async {
    messenger.setMockMethodCallHandler(wake, (c) async => c.method == 'status' ? 'No Vosk model in this build.' : null);
    final e = await VoskWakeWordEngine.create();
    expect(e.unavailableReason, 'No Vosk model in this build.');
  });

  test('armed only with the microphone allowed; a wake event calls back', () async {
    final calls = <String>[];
    var micGranted = false;
    messenger.setMockMethodCallHandler(wake, (c) async {
      calls.add(c.method);
      return null;
    });
    messenger.setMockMethodCallHandler(perms, (c) async => micGranted ? 1 : 0);
    late MockStreamHandlerEventSink sink;
    messenger.setMockStreamHandler(
      const EventChannel('planner/wake/events'),
      MockStreamHandler.inline(onListen: (_, s) => sink = s),
    );

    final e = await VoskWakeWordEngine.create();
    expect(e.available, isTrue);
    var woke = 0;
    await e.start(() => woke++);
    expect(calls, ['status'], reason: 'no microphone, no listening');

    micGranted = true;
    await e.start(() => woke++);
    expect(calls, ['status', 'start']);
    sink.success('wake');
    await Future<void>.delayed(Duration.zero);
    expect(woke, 1);

    await e.stop();
    expect(calls.last, 'stop');
    e.dispose();
  });
}
