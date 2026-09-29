import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/theme/planner_theme.dart';
import '../domain/capacity.dart';
import '../domain/time.dart';
import 'controls.dart';
import 'icons.dart';
import 'surfaces.dart';

/// `CapacityMeter(capacity, expanded)` (README 7.3). The whole meter is a
/// button that expands the equation panel.
class CapacityMeter extends StatelessWidget {
  const CapacityMeter({
    super.key,
    required this.cap,
    required this.expanded,
    required this.onToggle,
    required this.protectedNames,
    required this.fromNow,
    required this.weekend,
  });

  final Capacity cap;
  final bool expanded;
  final VoidCallback onToggle;

  /// "Getting ready, Wind-down" (or "None left").
  final String protectedNames;
  final bool fromNow, weekend;

  @override
  Widget build(BuildContext context) {
    final c = PlannerColors.of(context);
    final aria = '${dur(cap.planned)} planned of ${dur(cap.realistic)} realistic. '
        '${cap.over > 0 ? '${dur(cap.over)} over. ' : ''}Show how this is worked out.';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Pressable(
        onTap: onToggle,
        label: aria,
        radius: 4,
        pressedScale: 0.99,
        excludeChildSemantics: true,
        toggled: null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: Text.rich(TextSpan(children: [
                  TextSpan(
                      text: dur(cap.planned),
                      style: PlannerType.ui(12, weight: 500, color: c.tx)),
                  TextSpan(text: ' planned', style: PlannerType.ui(12, weight: 400, color: c.t2)),
                ])),
              ),
              Text.rich(TextSpan(children: [
                TextSpan(
                    text: dur(cap.realistic),
                    style: PlannerType.ui(12, weight: 500, color: c.tx)),
                TextSpan(text: ' realistic', style: PlannerType.ui(12, weight: 400, color: c.t2)),
              ])),
              const SizedBox(width: 4),
              AnimatedRotation(
                turns: expanded ? 0.75 : 0.25,
                duration: PlannerMotion.ms(context, 300),
                child: PlannerIcon(PIcon.chev, size: 14, stroke: 1.8, color: c.t3),
              ),
            ]),
            const SizedBox(height: 7),
            SizedBox(height: 16, child: CapacityBar(cap: cap)),
            const SizedBox(height: 3),
            Wrap(spacing: 12, runSpacing: 2, children: [
              for (final (k, v) in [
                ('AVAILABLE', cap.available),
                ('PROTECTED', cap.protectedMinutes),
                ('BREAKS', cap.breaks),
                ('BUFFER', cap.buffer),
              ])
                Text.rich(TextSpan(children: [
                  TextSpan(
                      text: '$k ',
                      style: PlannerType.stateLabel(size: 10, tracking: 0.04, weight: 500, color: c.t3)),
                  TextSpan(
                      text: dur(v),
                      style: PlannerType.stateLabel(size: 10, tracking: 0.04, weight: 500, color: c.t2)),
                ])),
            ]),
          ]),
        ),
      ),
      AnimatedSize(
        duration: PlannerMotion.ms(context, 420),
        curve: PlannerMotion.settleCurve,
        alignment: Alignment.topCenter,
        child: expanded ? _Equation(cap: cap, names: protectedNames, fromNow: fromNow, weekend: weekend) : const SizedBox(width: double.infinity),
      ),
    ]);
  }
}

/// The 8px bar with a 2px realistic marker overhanging by 4px.
class CapacityBar extends StatelessWidget {
  const CapacityBar({super.key, required this.cap, this.height = 8});
  final Capacity cap;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = PlannerColors.of(context);
    final d = PlannerMotion.ms(context, 620);
    const curve = PlannerMotion.boardCurve;
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      final cs = math.max(math.max(cap.available, cap.planned), 1);
      double px(num m) => m / cs * w;
      final top = (box.maxHeight - height) / 2;
      final real = cap.realistic;
      final children = <Widget>[
        Positioned(
          left: 0,
          right: 0,
          top: top,
          height: height,
          child: DecoratedBox(
              decoration: BoxDecoration(color: c.s1, borderRadius: BorderRadius.circular(2))),
        ),
      ];
      void seg(Key key, double l, double wd, Widget child) => children.add(AnimatedPositioned(
            key: key,
            duration: d,
            curve: curve,
            left: l,
            width: math.max(0, wd),
            top: top,
            height: height,
            child: child,
          ));
      // Zones right of the marker: breaks, buffer (dotted), protected (hatch).
      final z0 = real, z1 = z0 + cap.breaks, z2 = z1 + cap.buffer;
      seg(const ValueKey('z-brk'), px(z0), px(cap.breaks), ColoredBox(color: c.s2));
      seg(const ValueKey('z-buf'), px(z1), px(cap.buffer),
          CustomPaint(painter: DotsPainter(c.t3)));
      seg(const ValueKey('z-prot'), px(z2), px(math.max(0, cap.available - z2)),
          CustomPaint(painter: HatchPainter(color: c.t3, period: 4)));
      // Planned segments in time order, stripes past realistic.
      var acc = 0;
      for (final g in cap.segments) {
        final a = acc, b = acc + g.minutes;
        acc = b;
        final col = g.cat.color;
        final inW = math.min(b, real) - a;
        seg(ValueKey('s-${g.taskId}'), px(a), px(math.max(0, inW)),
            DecoratedBox(
              decoration: BoxDecoration(
                color: col,
                border: Border(right: BorderSide(color: c.bg, width: 1)),
              ),
            ));
        final oa = math.max(a, real);
        seg(ValueKey('o-${g.taskId}'), px(oa), px(math.max(0, b - oa)),
            CustomPaint(painter: HatchPainter(color: col, width: 2, period: 5)));
      }
      children.add(AnimatedPositioned(
        duration: d,
        curve: PlannerMotion.settleCurve,
        left: px(real) - 1,
        width: 2,
        top: top - 4,
        height: height + 8,
        child: DecoratedBox(
            decoration: BoxDecoration(color: c.tx, borderRadius: BorderRadius.circular(1))),
      ));
      return Stack(clipBehavior: Clip.none, children: children);
    });
  }
}

class _Equation extends StatelessWidget {
  const _Equation({required this.cap, required this.names, required this.fromNow, required this.weekend});
  final Capacity cap;
  final String names;
  final bool fromNow, weekend;

  @override
  Widget build(BuildContext context) {
    final c = PlannerColors.of(context);
    final rows = [
      ('', 'Available', cap.available,
          fromNow ? 'Outside fixed commitments, from now' : 'Outside fixed commitments', false),
      ('−', 'Protected', cap.protectedMinutes, names, false),
      ('−', 'Breaks', cap.breaks, '15 minutes after any block of 2 hours or more', false),
      ('−', 'Buffer', cap.buffer, 'Room for things that run over', false),
      ('=', 'Realistic', cap.realistic,
          weekend ? 'Capped at 6h on weekends until Planner knows your pace' : 'What Planner will schedule into',
          true),
    ];
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(color: c.s1, borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        for (final (i, r) in rows.indexed)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(
                border: i == 0 ? null : Border(top: BorderSide(color: c.ln))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 16, child: Text(r.$1, style: PlannerType.time(size: 13, weight: 500, color: c.t3))),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.$2, style: PlannerType.ui(13, weight: r.$5 ? 600 : 400, color: c.tx)),
                  const SizedBox(height: 1),
                  Text(r.$4, style: PlannerType.ui(11.5, weight: 400, color: c.t3)),
                ]),
              ),
              Text(dur(r.$3), style: PlannerType.time(size: 13, weight: r.$5 ? 600 : 400, color: c.tx)),
            ]),
          ),
      ]),
    );
  }
}
