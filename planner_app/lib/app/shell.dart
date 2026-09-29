import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/voice/planner_orb.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/note_strip.dart';
import 'state/clock.dart';
import 'state/derived.dart';
import 'state/note.dart';
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
    final wake = ref.watch(settingsProvider.select((s) => s.wakeWord));
    final bottom = mq.padding.bottom;
    final inSettings = _tab == AppTab.settings;
    return Scaffold(
      backgroundColor: c.bg,
      resizeToAvoidBottomInset: false,
      body: Stack(children: [
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
              showHey: _tab == AppTab.today && wake,
            ),
          ),
        ),
        // The orb, docked in the nav's centre slot.
        Positioned(
          left: 0,
          right: 0,
          bottom: bottom + kNavHeight - 30 - 50,
          height: 100,
          child: Center(
            child: Semantics(
              button: true,
              label: 'Talk to Planner',
              onTap: () => ref.read(noteProvider.notifier).say('Voice arrives in milestone 7.'),
              child: GestureDetector(
                onTap: () => ref.read(noteProvider.notifier).say('Voice arrives in milestone 7.'),
                child: SizedBox(
                  width: 100,
                  height: 100,
                  child: PlannerOrb(state: OrbState.idle, core: _coreColor(), size: 100),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: (inSettings ? 24 : 96) + bottom,
          child: const NoteStrip(),
        ),
      ]),
    );
  }

  /// Core = the current task's category, or warm white.
  Color? _coreColor() {
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
