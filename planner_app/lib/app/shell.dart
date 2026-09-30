import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/voice/planner_orb.dart';
import '../features/voice/voice_controller.dart';
import '../features/voice/voice_overlay.dart';
import '../features/voice/wake_word.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/note_strip.dart';
import '../widgets/planner_sheet.dart';
import 'state/actions.dart';
import 'state/clock.dart';
import 'state/derived.dart';
import 'state/staging.dart';
import 'state/ui_state.dart';
import 'theme/planner_theme.dart';

/// The phone shell: content panes, bottom nav with the centred orb, sheets,
/// voice and the note strip, stacked as in the prototype.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  AppTab _lastTab = AppTab.today;

  AppTab get _tab => AppTab.values[widget.shell.currentIndex];

  @override
  void didUpdateWidget(AppShell old) {
    super.didUpdateWidget(old);
    _syncTab();
  }

  @override
  void initState() {
    super.initState();
    _syncTab();
    WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(actionsProvider).topUpSeries());
  }

  void _syncTab() {
    final t = _tab;
    if (t != AppTab.settings) _lastTab = t;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(currentTabProvider.notifier).set(t);
    });
  }

  void _onTab(AppTab t) {
    // The settings icon toggles the push page.
    if (t == AppTab.settings && _tab == AppTab.settings) t = _lastTab;
    widget.shell.goBranch(t.index);
  }

  @override
  Widget build(BuildContext context) {
    final c = PlannerColors.of(context);
    final mq = MediaQuery.of(context);
    final navBump = ref.watch(stagingProvider.select((s) => s.navBump));
    final bump = navBump > 0 && DateTime.now().millisecondsSinceEpoch - navBump < 700;
    final bottom = mq.padding.bottom;
    final inSettings = _tab == AppTab.settings;
    return Scaffold(
      backgroundColor: c.bg,
      resizeToAvoidBottomInset: false,
      body: WakeWordHost(
        child: AppEntrance(
          child: Stack(children: [
            Positioned(
              top: mq.padding.top,
              left: 0,
              right: 0,
              bottom: kNavHeight + bottom,
              child: widget.shell,
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                color: c.bg,
                padding: EdgeInsets.only(bottom: bottom),
                child: BottomNav(
                  tab: _tab,
                  onTab: _onTab,
                  planBump: bump,
                  showHey: ref.watch(showHeyCaptionProvider),
                ),
              ),
            ),
            // Prototype z-order: veil 20, orb 30, sheets 50, note 55.
            const Positioned.fill(child: VoiceOverlay()),
            _OrbLayer(core: _coreColor()),
            const Positioned.fill(child: SheetHost()),
            Positioned(
              left: 16,
              right: 16,
              bottom: (inSettings ? 24 : 96) + bottom,
              child: const NoteStrip(),
            ),
          ]),
        ),
      ),
    );
  }

  /// Core = the voice result's category, the current task's, or warm white.
  Color? _coreColor() {
    final vc = ref.watch(voiceControllerProvider.select((v) => v.open ? v.res?.core : null));
    if (vc != null) return vc.color;
    final tasks = ref.watch(visibleTasksProvider);
    final today = ref.watch(todayProvider);
    final now = ref.watch(nowMinuteProvider);
    for (final t in tasks) {
      if (t.day == today && t.isLive && !t.done && now >= t.start! && now < t.end!) {
        return t.cat.color;
      }
    }
    return null;
  }
}

/// Panes: the active one sits in place; the others wait ±24% aside, faded
/// and blurred. Settings slides in from the right over the current pane.
class PaneSwitcher extends StatefulWidget {
  const PaneSwitcher({super.key, required this.index, required this.children});
  final int index;
  final List<Widget> children;

  @override
  State<PaneSwitcher> createState() => _PaneSwitcherState();
}

class _PaneSwitcherState extends State<PaneSwitcher> {
  int _lastMain = 0;

  @override
  Widget build(BuildContext context) {
    final settings = widget.index == AppTab.settings.index;
    if (!settings) _lastMain = widget.index;
    final ci = _lastMain;
    final reduced = PlannerMotion.reduced(context);
    final c = PlannerColors.of(context);
    return Stack(children: [
      for (var k = 0; k < 3; k++)
        _Pane(
          key: ValueKey('pane$k'),
          on: widget.index == k,
          dx: k < ci ? -0.24 : 0.24,
          blur: !reduced,
          child: widget.children[k],
        ),
      // Settings push page.
      IgnorePointer(
        ignoring: !settings,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: settings ? 0 : 1),
          duration: PlannerMotion.ms(context, 420),
          curve: PlannerMotion.settleCurve,
          builder: (context, v, child) => v >= 0.999
              ? const SizedBox.shrink()
              : FractionalTranslation(translation: Offset(v, 0), child: child),
          child: ColoredBox(
            color: c.bg,
            child: TickerMode(enabled: settings, child: widget.children[3]),
          ),
        ),
      ),
    ]);
  }
}

class _Pane extends StatelessWidget {
  const _Pane({super.key, required this.on, required this.dx, required this.blur, required this.child});
  final bool on, blur;
  final double dx;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !on,
      child: ExcludeSemantics(
        excluding: !on,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: on ? 1 : 0),
          duration: PlannerMotion.ms(context, 520),
          curve: PlannerMotion.settleCurve,
          child: TickerMode(enabled: on, child: child),
          builder: (context, v, child) {
            if (v <= 0.001) return Offstage(child: child);
            Widget w = FractionalTranslation(
              translation: Offset(dx * (1 - v), 0),
              child: Opacity(opacity: Curves.easeOut.transform(v), child: child),
            );
            if (blur && v < 0.999) {
              final s = 8 * (1 - v);
              w = ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: s, sigmaY: s), child: w);
            }
            return w;
          },
        ),
      ),
    );
  }
}


/// The Planner Orb: docked in the nav at 0.42, it rises to the upper centre
/// at 1.1 over 760ms Cubic(.34, 1.22, .5, 1) when voice opens. Tapping it
/// works anywhere in the app.
class _OrbLayer extends ConsumerStatefulWidget {
  const _OrbLayer({required this.core});
  final Color? core;

  @override
  ConsumerState<_OrbLayer> createState() => _OrbLayerState();
}

class _OrbLayerState extends ConsumerState<_OrbLayer> {
  /// Desktop and web: the docked orb livens up under the pointer (amp .16).
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final v = ref.watch(voiceControllerProvider);
    final level = ref.watch(orbLevelProvider);
    final mq = MediaQuery.of(context);
    final k = (mq.size.height / 860).clamp(0.78, 1.2);
    final docked = mq.size.height - mq.padding.bottom - kNavHeight + 30;
    final top = 320 * k;
    return Positioned.fill(
      child: Stack(children: [
        TweenAnimationBuilder<double>(
          tween: Tween(end: v.open ? 1 : 0),
          duration: PlannerMotion.ms(context, 760),
          curve: PlannerMotion.wakeCurve,
          builder: (context, t, child) {
            final cy = docked + (top - docked) * t;
            final scale = 0.42 + (1.1 - 0.42) * t;
            return Positioned(
              left: mq.size.width / 2 - 120,
              top: cy - 120,
              width: 240,
              height: 240,
              child: IgnorePointer(child: Transform.scale(scale: scale, child: child)),
            );
          },
          child: PlannerOrb(
            state: v.phase,
            core: widget.core,
            hover: _hover && !v.open,
            level: level,
            speaking: v.speaking,
            controller: ref.watch(orbControllerProvider),
            size: 240,
          ),
        ),
        if (!v.open)
          Positioned(
            left: mq.size.width / 2 - 32,
            top: docked - 32,
            width: 64,
            height: 64,
            child: Semantics(
              button: true,
              label: 'Talk to Planner',
              onTap: ref.read(voiceControllerProvider.notifier).tapOrb,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) => setState(() => _hover = true),
                onExit: (_) => setState(() => _hover = false),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: ref.read(voiceControllerProvider.notifier).tapOrb,
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Set just before the shell is revealed from onboarding, so it scales in
/// from 0.98 while onboarding scales to 1.03 and blurs out (Settle).
class EntrancePending extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool v) => state = v;
}

final entrancePendingProvider = NotifierProvider<EntrancePending, bool>(EntrancePending.new);

class AppEntrance extends ConsumerStatefulWidget {
  const AppEntrance({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<AppEntrance> createState() => _AppEntranceState();
}

class _AppEntranceState extends ConsumerState<AppEntrance> with SingleTickerProviderStateMixin {
  late final AnimationController _a =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 420), value: 1);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      if (ref.read(entrancePendingProvider)) _play();
    }
  }

  void _play() {
    _a.duration = PlannerMotion.ms(context, 420);
    _a.forward(from: 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(entrancePendingProvider.notifier).set(false);
    });
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(entrancePendingProvider, (_, v) {
      if (v) _play();
    });
    // The tree shape never changes, so the shell keeps its state.
    return AnimatedBuilder(
      animation: _a,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: Curves.easeOut.transform(_a.value),
        child: Transform.scale(
          scale: 0.98 + 0.02 * PlannerMotion.settleCurve.transform(_a.value),
          child: child,
        ),
      ),
    );
  }
}
