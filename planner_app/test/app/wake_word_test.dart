import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planner_app/app/dev/scenarios.dart';
import 'package:planner_app/app/state/actions.dart';
import 'package:planner_app/app/state/store.dart';
import 'package:planner_app/app/state/ui_state.dart';
import 'package:planner_app/features/voice/planner_orb.dart';
import 'package:planner_app/features/voice/voice_controller.dart';
import 'package:planner_app/features/voice/speech.dart';
import 'package:planner_app/features/voice/wake_word.dart';

import 'harness.dart';

class FakeSpotter implements WakeWordEngine {
  bool running = false;
  int starts = 0;
  VoidCallback? onWake;

  @override
  bool get available => true;
  @override
  String? get unavailableReason => null;

  @override
  Future<void> start(VoidCallback onWake, {List<String> phrases = const []}) async {
    running = true;
    starts++;
    this.onWake = onWake;
  }

  @override
  Future<void> stop() async => running = false;

  @override
  HandOverSpeech? takeOver() => null;

  void hear() => onWake?.call();
}

void main() {
  testWidgets('the spotter runs only while Today is on screen and resumed', (tester) async {
    final spot = FakeSpotter();
    final h = await pumpScenario(tester, Scenario.tue,
        overrides: [wakeWordEngineProvider.overrideWithValue(spot)]);
    final act = h.container.read(actionsProvider);
    expect(spot.running, isTrue);
    expect(h.container.read(showHeyCaptionProvider), isTrue);

    act.goTab(AppTab.plan);
    await h.settle(600);
    expect(spot.running, isFalse, reason: 'route change stops it');

    act.goTab(AppTab.today);
    await h.settle(600);
    expect(spot.running, isTrue);

    act.openCreate();
    await h.settle(300);
    expect(spot.running, isFalse, reason: 'a sheet stops it');
    act.closeSheet();
    await h.settle(600);
    expect(spot.running, isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(spot.running, isFalse, reason: 'pause stops it');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(spot.running, isFalse, reason: 'arming waits for the microphone to be free');
    await h.settle(500);
    expect(spot.running, isTrue);

    // Hearing the phrase releases the microphone first, then opens voice.
    spot.hear();
    await tester.pump();
    expect(spot.running, isFalse);
    expect(h.container.read(voiceControllerProvider).phase, OrbState.wake);
    h.container.read(voiceControllerProvider.notifier).close();
    await h.settle(600);
    expect(spot.running, isTrue);
    expect(spot.starts, 5);

    // Switched off in Settings: never armed.
    final store = h.container.read(plannerStoreProvider.notifier);
    await store.setSettings(h.data.settings.copyWith(wakeWord: false));
    await tester.pump();
    expect(spot.running, isFalse);
    expect(h.container.read(showHeyCaptionProvider), isFalse);
    await h.dispose();
  });

  testWidgets('"Say Hey Planner" follows the same gate', (tester) async {
    final h = await pumpScenario(tester, Scenario.tue);
    final act = h.container.read(actionsProvider);
    final voice = h.container.read(voiceControllerProvider.notifier);

    act.goTab(AppTab.plan);
    await h.settle(600);
    voice.sayHey();
    await tester.pump();
    expect(h.container.read(voiceControllerProvider).open, isFalse);
    expect(find.text('“Hey Planner” works only while Today is open on screen.'), findsOneWidget);

    act.goTab(AppTab.today);
    await h.settle(600);
    final store = h.container.read(plannerStoreProvider.notifier);
    await store.setSettings(h.data.settings.copyWith(wakeWord: false));
    await tester.pump();
    voice.sayHey();
    await tester.pump();
    expect(h.container.read(voiceControllerProvider).open, isFalse);
    expect(find.text('The wake phrase is off. Turn it on in Settings, Voice.'), findsOneWidget);

    await store.setSettings(h.data.settings.copyWith(wakeWord: true));
    await tester.pump();
    voice.sayHey();
    await tester.pump();
    expect(h.container.read(voiceControllerProvider).phase, OrbState.wake);
    voice.close();
    await h.dispose();
  });
}
