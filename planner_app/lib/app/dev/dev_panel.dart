import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/settings.dart';
import '../../data/backup/sync.dart';
import '../../domain/intents.dart';
import '../../features/voice/speech.dart';
import '../../widgets/controls.dart';
import '../state/actions.dart';
import '../state/clock.dart';
import '../state/derived.dart';
import '../state/note.dart';
import '../state/staging.dart';
import '../state/store.dart';
import '../state/ui_state.dart';
import '../router.dart';
import '../theme/planner_theme.dart';
import '../../features/voice/voice_controller.dart';
import 'foundations_page.dart';
import 'scenarios.dart';

/// Loads a journey step: replaces the data, pins the clock, resets staging.
Future<void> loadScenario(WidgetRef ref, Scenario k) async {
  final s = buildScenario(k);
  ref.read(actionsProvider).seq.clear();
  ref.read(stagingProvider.notifier).reset();
  ref.read(noteProvider.notifier).dismiss();
  ref.read(sheetProvider.notifier).close();
  ref.read(voiceControllerProvider.notifier).close();
  final settings = ref.read(settingsProvider);
  await ref.read(plannerStoreProvider.notifier).replaceAll(s.data.copyWith(settings: settings));
  ref.read(clockProvider.notifier).pin(s.clock);
  ref.read(todayUiProvider.notifier).set((u) => const TodayUi());
  if (!s.data.onboarded) {
    ref.read(routerProvider).go(onboardingPath);
    return;
  }
  final tab = switch (k) {
    Scenario.week => AppTab.plan,
    Scenario.sunday => AppTab.progress,
    Scenario.settings => AppTab.settings,
    _ => AppTab.today,
  };
  if (k == Scenario.week) {
    ref.read(planUiProvider.notifier).set((p) => PlanUi(seg: PlanSeg.week, weekSel: s.data.installedDay! + 2));
  }
  ref.read(actionsProvider).goTab(tab);
  if (k == Scenario.sunday) ref.read(actionsProvider).seq.at(400, ref.read(actionsProvider).openReview);
}

/// Debug-only mirror of the prototype's control panel.
class DevPanel extends ConsumerWidget {
  const DevPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = PlannerColors.of(context);
    final clock = ref.watch(clockProvider);
    final clk = ref.read(clockProvider.notifier);
    final settings = ref.watch(settingsProvider);
    final store = ref.read(plannerStoreProvider.notifier);
    final online = ref.watch(onlineProvider);
    final voice = ref.watch(voiceDebugProvider);
    Widget label(String t) => Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 6),
          child: Text(t, style: PlannerType.stateLabel(size: 10, tracking: 0.1, color: c.t3)),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      label('DEVELOPER · JOURNEY'),
      for (final (i, k) in Scenario.values.indexed)
        Pressable(
          onTap: () => loadScenario(ref, k),
          label: k.title,
          radius: 8,
          pressedScale: 0.99,
          excludeChildSemantics: true,
          child: Container(
            height: 44,
            alignment: Alignment.centerLeft,
            child: Row(children: [
              SizedBox(width: 22, child: Text('${i + 1}', style: PlannerType.time(size: 11, color: c.t3))),
              Text(k.title, style: PlannerType.ui(13.5, color: c.tx)),
            ]),
          ),
        ),
      label('CLOCK ${clk.isVirtual ? '(PINNED)' : ''}  ${clock.toString().substring(0, 16)}'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        SecondaryPill(label: 'Clock +30 min', height: 36, onTap: () => clk.advance(const Duration(minutes: 30))),
        SecondaryPill(
            label: clk.speed > 1 ? 'Speed 1×' : 'Speed 60×',
            height: 36,
            onTap: () => clk.setSpeed(clk.speed > 1 ? 1 : 60)),
        SecondaryPill(label: 'Real time', height: 36, onTap: clk.useRealTime),
      ]),
      label('DEMO VOICE (TAP THE ORB)'),
      for (final (i, line) in demoUtterances.indexed)
        Pressable(
          onTap: () => ref.read(voiceDebugProvider.notifier).set((v) => v.copyWith(line: i)),
          label: line,
          radius: 8,
          pressedScale: 0.99,
          excludeChildSemantics: true,
          child: Container(
            constraints: const BoxConstraints(minHeight: 40),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            margin: const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(
              color: voice.line == i ? c.s2 : null,
              border: Border.all(color: c.ln),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.centerLeft,
            child: Text(line, style: PlannerType.ui(12.5, weight: 400, color: c.tx)),
          ),
        ),
      Wrap(spacing: 8, runSpacing: 8, children: [
        // Same gating as the real wake phrase: Today must be on screen.
        SecondaryPill(
          label: 'Say “Hey Planner”',
          height: 36,
          onTap: ref.read(voiceControllerProvider.notifier).sayHey,
        ),
        SecondaryPill(
          label: 'Go to Today and say it',
          height: 36,
          onTap: () {
            ref.read(actionsProvider).goTab(AppTab.today);
            ref.read(actionsProvider).seq.at(900, ref.read(voiceControllerProvider.notifier).sayHey);
          },
        ),
        SecondaryPill(
          label: voice.live ? 'Voice: live mic' : 'Voice: demo',
          height: 36,
          onTap: () => ref.read(voiceDebugProvider.notifier).set((v) => v.copyWith(live: !v.live)),
        ),
        SecondaryPill(
          label: voice.micAllowed ? 'Mic: allowed' : 'Mic: denied',
          height: 36,
          onTap: () => ref.read(voiceDebugProvider.notifier).set((v) => v.copyWith(micAllowed: !v.micAllowed)),
        ),
      ]),
      label('SWITCHES'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        SecondaryPill(
          label: 'Theme: ${settings.theme.name}',
          height: 36,
          onTap: () => store.setSettings(settings.copyWith(
              theme: ThemeChoice.values[(settings.theme.index + 1) % 3])),
        ),
        SecondaryPill(
          label: 'Motion: ${settings.motion.name}',
          height: 36,
          onTap: () => store.setSettings(settings.copyWith(
              motion: MotionChoice.values[(settings.motion.index + 1) % 3])),
        ),
        SecondaryPill(
          label: online ? 'Network: online' : 'Network: offline',
          height: 36,
          onTap: () => ref.read(onlineProvider.notifier).set(!online),
        ),
        SecondaryPill(
          label: 'Simulate a Drive conflict',
          height: 36,
          onTap: () async {
            await ref.read(syncProvider.notifier).debugConflict();
            ref.read(actionsProvider).openDrivePage();
          },
        ),
        SecondaryPill(
          label: 'Foundations',
          height: 36,
          onTap: () => Navigator.of(context, rootNavigator: true)
              .push(MaterialPageRoute<void>(builder: (_) => const FoundationsPage())),
        ),
      ]),
    ]);
  }
}
