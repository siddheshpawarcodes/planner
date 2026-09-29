import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/state/actions.dart';
import '../../app/state/staging.dart';
import '../../app/state/ui_state.dart';
import '../../app/theme/planner_theme.dart';
import '../../data/settings.dart';
import '../../domain/time.dart';
import '../../widgets/capacity_meter.dart';
import '../../widgets/controls.dart';
import '../../widgets/icons.dart';
import 'today_model.dart';

class TodayHeader extends ConsumerWidget {
  const TodayHeader({super.key, required this.compact});

  /// Tablet/desktop rails drop the view switch.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = PlannerColors.of(context);
    final m = ref.watch(todayModelProvider);
    final ui = ref.watch(todayUiProvider);
    final online = ref.watch(onlineProvider);
    final act = ref.read(actionsProvider);
    final navBump = ref.watch(stagingProvider.select((s) => s.navBump));
    final bumping = navBump > 0 &&
        DateTime.now().millisecondsSinceEpoch - navBump < 700;
    final (label, title, meta) = m.nowLine;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: 44,
          child: Row(children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(dayLabel(m.day),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PlannerType.bricolage600(21, height: 1.1, tracking: -0.01, color: c.tx)),
              ),
            ),
            if (!online)
              Pressable(
                onTap: act.offlineInfo,
                label: 'Offline. Saved on this phone.',
                excludeChildSemantics: true,
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(color: c.s1, borderRadius: BorderRadius.circular(999)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    PlannerIcon(PIcon.cloudOff, size: 15, color: c.t2, stroke: 1.6),
                    const SizedBox(width: 6),
                    Text('LOCAL', style: PlannerType.stateLabel(size: 11, tracking: 0, weight: 500, color: c.t2)),
                  ]),
                ),
              ),
            PlannerIconButton(
              icon: PIcon.plus,
              label: 'Add task',
              onTap: () => act.openCreate(date: m.day),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        Row(children: [
          SegmentedPill<int>(
            label: 'Day',
            width: 184,
            options: const [(0, 'Today'), (1, 'Tomorrow')],
            value: ui.dayOffset,
            onChanged: act.setDay,
            bumpIndex: bumping ? 1 : null,
          ),
          const Spacer(),
          if (!compact)
            SegmentedPill<TodayView>(
              label: 'View',
              width: 112,
              outlined: true,
              fontSize: 12,
              options: const [(TodayView.strip, 'Strip'), (TodayView.dial, 'Dial')],
              value: ui.view,
              onChanged: (v) => ref.read(todayUiProvider.notifier).set(
                  (s) => s.copyWith(view: v, dialIn: v != TodayView.dial)),
            ),
        ]),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: label, style: PlannerType.body(size: 14, weight: 600, color: c.tx)),
                  TextSpan(text: '  $title', style: PlannerType.body(size: 14, color: c.tx)),
                  if (meta.isNotEmpty)
                    TextSpan(text: '  $meta', style: PlannerType.body(size: 14, color: c.t3)),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _Odometer(
            n: m.isToday ? m.doneCount : m.dayTasks.length,
            den: m.isToday ? '/ ${m.dayTasks.length}' : '',
            label: m.isToday ? 'DONE' : 'PLANNED',
            aria: m.isToday
                ? '${m.doneCount} of ${m.dayTasks.length} done'
                : '${m.dayTasks.length} planned',
          ),
        ]),
        const SizedBox(height: 10),
        _SegmentBar(m: m),
        const SizedBox(height: 10),
        CapacityMeter(
          cap: m.cap,
          expanded: ui.capOpen,
          onToggle: () =>
              ref.read(todayUiProvider.notifier).set((s) => s.copyWith(capOpen: !s.capOpen)),
          protectedNames: m.protectedNames,
          fromNow: m.isToday,
          weekend: isWeekend(m.day),
        ),
        AnimatedSize(
          duration: PlannerMotion.ms(context, 420),
          curve: PlannerMotion.settleCurve,
          child: Column(children: [
            if (m.showOver) ...[
              const SizedBox(height: 10),
              CalmRow(
                actions: [
                  PrimaryPill(label: m.overButton, onTap: () => act.moveOver(m.day), padding: 14),
                  TextPill(label: 'Keep anyway', onTap: () => act.keepOver(m.day)),
                ],
                child: Text(m.overText, style: PlannerType.body(size: 12.5, color: c.tx).copyWith(height: 1.35)),
              ),
            ] else if (m.showMissed) ...[
              const SizedBox(height: 10),
              CalmRow(
                actions: [
                  PrimaryPill(
                      label: 'Decide',
                      onTap: () => act.openDecision(m.missedList.first.id)),
                  TextPill(
                      label: 'Later',
                      onTap: () => act.missedLater(m.missedList.map((t) => t.id))),
                ],
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(m.missedText, style: PlannerType.ui(13, color: c.tx)),
                  const SizedBox(height: 1),
                  Text('What should we do with it?', style: PlannerType.ui(12, weight: 400, color: c.t2)),
                ]),
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}

/// Rolling digit (700ms Spring) over a total, with DONE or PLANNED.
class _Odometer extends StatelessWidget {
  const _Odometer({required this.n, required this.den, required this.label, required this.aria});
  final int n;
  final String den, label, aria;

  @override
  Widget build(BuildContext context) {
    final c = PlannerColors.of(context);
    final style = PlannerType.ui(22, weight: 400, color: c.tx, tracking: -0.02)
        .copyWith(height: 1.1, fontFeatures: const [FontFeature.tabularFigures()]);
    const h = 22 * 1.1;
    return Semantics(
      label: aria,
      liveRegion: true,
      excludeSemantics: true,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
        if (n > 9)
          Text('$n', style: style)
        else
          SizedBox(
            height: h,
            width: (TextPainter(
              text: TextSpan(text: '0', style: style),
              textDirection: TextDirection.ltr,
              textScaler: MediaQuery.textScalerOf(context),
            )..layout())
                .width,
            child: ClipRect(
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: n.toDouble()),
                duration: PlannerMotion.ms(context, 700),
                curve: const Cubic(0.34, 1.45, 0.55, 1),
                builder: (context, v, _) => OverflowBox(
                  alignment: Alignment.topCenter,
                  maxHeight: h * 10,
                  child: Transform.translate(
                    offset: Offset(0, -v * h),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      for (var i = 0; i < 10; i++)
                        SizedBox(height: h, child: Text('$i', style: style)),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        if (den.isNotEmpty) ...[
          const SizedBox(width: 3),
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(den, style: PlannerType.ui(15, weight: 400, color: c.t3)),
          ),
        ],
        const SizedBox(width: 5),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(label, style: PlannerType.stateLabel(size: 10, tracking: 0.08, weight: 500, color: c.t3)),
        ),
      ]),
    );
  }
}

/// One 3px segment per task, filling in the task's category colour when
/// done (Today) or placed (Tomorrow).
class _SegmentBar extends StatelessWidget {
  const _SegmentBar({required this.m});
  final TodayModel m;

  @override
  Widget build(BuildContext context) {
    final c = PlannerColors.of(context);
    final ts = m.dayTasks;
    final items = ts.isEmpty ? [null] : ts;
    return ExcludeSemantics(
      child: Row(children: [
        for (final (i, t) in items.indexed) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: Container(
              height: 3,
              decoration: BoxDecoration(color: c.ln, borderRadius: BorderRadius.circular(1)),
              clipBehavior: Clip.antiAlias,
              child: t == null
                  ? null
                  : TweenAnimationBuilder<double>(
                      tween: Tween(end: (m.isToday ? t.done : true) ? 1 : 0),
                      duration: PlannerMotion.ms(context, 520 + i * 40),
                      curve: Interval(
                          (i * 40) / (520 + i * 40), 1, curve: PlannerMotion.settleCurve),
                      builder: (context, v, _) => FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: v,
                        child: ColoredBox(color: t.cat.color),
                      ),
                    ),
            ),
          ),
        ],
      ]),
    );
  }
}
