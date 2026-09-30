import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/layout.dart';
import '../app/state/clock.dart';
import '../app/state/derived.dart';
import '../app/state/store.dart';
import '../app/state/ui_state.dart';
import '../app/theme/planner_theme.dart';
import '../data/backup/sync.dart';
import '../domain/capacity.dart';
import '../domain/time.dart';
import '../features/voice/wake_word.dart';
import 'controls.dart';
import 'icons.dart';
import 'surfaces.dart';

/// Where the docked orb sits in the rail or sidebar (its centre).
Offset railOrbCenter(Size screen) => Offset(kRailWidth / 2, screen.height / 2);
const kSidebarOrbCenter = Offset(20 + 32, 376);

class _NavItem extends StatelessWidget {
  const _NavItem({required this.label, required this.on, required this.onTap, this.keyHint, this.bump = false});
  final String label;
  final bool on, bump;
  final VoidCallback onTap;
  final String? keyHint;

  @override
  Widget build(BuildContext context) {
    final c = PlannerColors.of(context);
    return Pressable(
      onTap: onTap,
      label: keyHint == null ? label : '$label, shortcut $keyHint',
      selected: on,
      radius: 8,
      pressedScale: 0.97,
      excludeChildSemantics: true,
      child: AnimatedContainer(
        duration: PlannerMotion.of(context, PlannerMotion.snap),
        height: keyHint == null ? 56 : 40,
        padding: EdgeInsets.symmetric(horizontal: keyHint == null ? 0 : 12),
        decoration: BoxDecoration(
          color: keyHint != null && on ? c.s1 : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: keyHint == null
            ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Bump(
                  on: bump,
                  scale: 1.12,
                  child: Text(label, style: PlannerType.ui(13, color: on ? c.tx : c.t3)),
                ),
                const SizedBox(height: 6),
                AnimatedContainer(
                  duration: PlannerMotion.of(context, PlannerMotion.snap),
                  width: on ? 16 : 0,
                  height: 2,
                  decoration: BoxDecoration(color: c.tx, borderRadius: BorderRadius.circular(1)),
                ),
              ])
            : Row(children: [
                Expanded(
                  child: Bump(
                    on: bump,
                    scale: 1.06,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(label, style: PlannerType.ui(14, color: on ? c.tx : c.t2)),
                    ),
                  ),
                ),
                Text(keyHint!, style: PlannerType.time(size: 11, weight: 500, color: c.t3)),
              ]),
      ),
    );
  }
}

/// Tablet: Today and Plan above the orb, Progress and settings below it,
/// the orb vertically centred (the orb itself is drawn by the shell).
class NavRail extends ConsumerWidget {
  const NavRail({super.key, required this.tab, required this.onTab, required this.planBump});
  final AppTab tab;
  final ValueChanged<AppTab> onTab;
  final bool planBump;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = PlannerColors.of(context);
    final hey = ref.watch(showHeyCaptionProvider);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Primary',
      child: Container(
        width: kRailWidth,
        decoration: BoxDecoration(color: c.bg, border: Border(right: BorderSide(color: c.ln))),
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 6),
        // Items fill the rail's width: every target stays at least 44px.
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _NavItem(label: 'Today', on: tab == AppTab.today, onTap: () => onTab(AppTab.today)),
          const SizedBox(height: 4),
          _NavItem(label: 'Plan', on: tab == AppTab.plan, onTap: () => onTab(AppTab.plan), bump: planBump),
          const Spacer(),
          // The orb's slot (the shell draws the orb here).
          const SizedBox(height: 72),
          SizedBox(
            height: 16,
            child: AnimatedOpacity(
              alwaysIncludeSemantics: false,
              opacity: hey ? 1 : 0,
              duration: PlannerMotion.ms(context, 300),
              child: ExcludeSemantics(
                child: Text('HEY PLANNER',
                    textAlign: TextAlign.center,
                    style: PlannerType.stateLabel(size: 8, tracking: 0.1, weight: 500, color: c.t3)),
              ),
            ),
          ),
          const Spacer(),
          _NavItem(label: 'Progress', on: tab == AppTab.progress, onTap: () => onTab(AppTab.progress)),
          const SizedBox(height: 4),
          Center(
            child: PlannerIconButton(
              icon: PIcon.sliders,
              label: 'Settings',
              onTap: () => onTab(AppTab.settings),
              color: tab == AppTab.settings ? c.tx : c.t3,
              size: 20,
            ),
          ),
        ]),
      ),
    );
  }
}

/// Desktop: nav with key hints, the week summary with 7 mini load bars, the
/// docked orb with "Talk to Planner V", sync status and settings.
class Sidebar extends ConsumerWidget {
  const Sidebar({super.key, required this.tab, required this.onTab, required this.planBump});
  final AppTab tab;
  final ValueChanged<AppTab> onTab;
  final bool planBump;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = PlannerColors.of(context);
    final today = ref.watch(todayProvider);
    final routine = ref.watch(routineProvider);
    final tasks = ref.watch(effectiveTasksProvider);
    final hey = ref.watch(showHeyCaptionProvider);
    final ws = weekStart(today);
    final days = [
      for (var d = ws; d < ws + 7; d++)
        (
          tasks.where((t) => t.day == d && t.isLive).fold(0, (a, t) => a + t.end! - t.start!),
          capOf(d, routine, tasks, 0).realistic,
        )
    ];
    final planned = days.fold(0, (a, x) => a + x.$1), real = days.fold(0, (a, x) => a + x.$2);
    final sync = ref.watch(syncProvider);
    final data = ref.watch(plannerStoreProvider);
    final online = ref.watch(onlineProvider);
    final status = driveStatusText(sync, data, online: online, now: DateTime.now());

    return Container(
      width: kSidebarWidth,
      decoration: BoxDecoration(color: c.bg, border: Border(right: BorderSide(color: c.ln))),
      child: Stack(children: [
        Positioned(
          left: 20,
          right: 20,
          top: 24,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Planner', style: PlannerType.bricolage600(20, color: c.tx)),
            const SizedBox(height: 22),
            _NavItem(label: 'Today', keyHint: 'T', on: tab == AppTab.today, onTap: () => onTab(AppTab.today)),
            const SizedBox(height: 4),
            _NavItem(
                label: 'Plan', keyHint: 'P', on: tab == AppTab.plan, onTap: () => onTab(AppTab.plan), bump: planBump),
            const SizedBox(height: 4),
            _NavItem(label: 'Progress', keyHint: 'G', on: tab == AppTab.progress, onTap: () => onTab(AppTab.progress)),
            const SizedBox(height: 24),
            Text('This week', style: PlannerType.bricolage600(15, color: c.tx)),
            const SizedBox(height: 4),
            Text.rich(
              TextSpan(children: [
                TextSpan(text: dur(planned), style: PlannerType.ui(12, color: c.tx)),
                TextSpan(text: ' planned of ', style: PlannerType.ui(12, weight: 400, color: c.t3)),
                TextSpan(text: dur(real), style: PlannerType.ui(12, color: c.tx)),
                TextSpan(text: ' realistic', style: PlannerType.ui(12, weight: 400, color: c.t3)),
              ]),
            ),
            const SizedBox(height: 10),
            Semantics(
              label: 'Week load: ${[
                for (var i = 0; i < 7; i++) '${dayLongNames[i]} ${dur(days[i].$1)} of ${dur(days[i].$2)}'
              ].join(', ')}',
              excludeSemantics: true,
              child: Row(children: [
                for (var i = 0; i < 7; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(child: _MiniLoad(planned: days[i].$1, realistic: days[i].$2, letter: dayLetters[i], today: ws + i == today)),
                ],
              ]),
            ),
          ]),
        ),
        // The orb card: the shell draws the orb at kSidebarOrbCenter.
        Positioned(
          left: 12,
          right: 12,
          top: kSidebarOrbCenter.dy - 46,
          height: 92,
          child: Container(
            decoration: BoxDecoration(color: c.s1, borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.only(left: 76, right: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Row(children: [
                Expanded(child: Text('Talk to Planner', style: PlannerType.ui(13, color: c.tx))),
                Text('V', style: PlannerType.time(size: 11, weight: 500, color: c.t3)),
              ]),
              const SizedBox(height: 3),
              AnimatedOpacity(
                opacity: hey ? 1 : 0.5,
                duration: PlannerMotion.ms(context, 300),
                child: Text('Or say “Hey Planner” while Today is on screen.',
                    maxLines: 3, style: PlannerType.ui(11, weight: 400, color: c.t3).copyWith(height: 1.3)),
              ),
            ]),
          ),
        ),
        Positioned(
          left: 20,
          right: 12,
          bottom: 16,
          child: Row(children: [
            PlannerIcon(!online && sync.connected ? PIcon.cloudOff : PIcon.cloud, size: 16, color: c.t3),
            const SizedBox(width: 8),
            Expanded(
              child: Text(status, maxLines: 1, overflow: TextOverflow.ellipsis, style: PlannerType.ui(12, weight: 400, color: c.t3)),
            ),
            PlannerIconButton(
              icon: PIcon.sliders,
              label: 'Settings',
              onTap: () => onTab(AppTab.settings),
              color: tab == AppTab.settings ? c.tx : c.t3,
              size: 20,
            ),
          ]),
        ),
      ]),
    );
  }
}

class _MiniLoad extends StatelessWidget {
  const _MiniLoad({required this.planned, required this.realistic, required this.letter, required this.today});
  final int planned, realistic;
  final String letter;
  final bool today;

  @override
  Widget build(BuildContext context) {
    final c = PlannerColors.of(context);
    final cap = math.max(1, realistic);
    final fill = math.min(1.0, planned / cap);
    final over = planned > realistic;
    return Column(children: [
      SizedBox(
        height: 28,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: Stack(children: [
            Positioned.fill(child: ColoredBox(color: c.s1)),
            Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                heightFactor: fill,
                widthFactor: 1,
                child: over
                    ? CustomPaint(painter: HatchPainter(color: c.tx, width: 1.5, period: 3.5))
                    : ColoredBox(color: c.tx),
              ),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 4),
      Text(letter, style: PlannerType.time(size: 10, weight: today ? 600 : 500, color: today ? c.tx : c.t3)),
    ]);
  }
}
