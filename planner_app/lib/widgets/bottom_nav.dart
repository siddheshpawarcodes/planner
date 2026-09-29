import 'package:flutter/material.dart';

import '../app/state/ui_state.dart';
import '../app/theme/planner_theme.dart';
import 'controls.dart';
import 'icons.dart';

const double kNavHeight = 84;

/// `BottomNav` (README 7.7): 84px, 1px top hairline, a centred 92px orb slot
/// (`1fr 1fr 92px 1fr 1fr`), active 16 × 2 `tx` bar with a scaleX spring.
class BottomNav extends StatelessWidget {
  const BottomNav({
    super.key,
    required this.tab,
    required this.onTab,
    required this.planBump,
    required this.showHey,
  });

  final AppTab tab;
  final ValueChanged<AppTab> onTab;
  final bool planBump;

  /// "HEY PLANNER": the wake phrase is available (Today only).
  final bool showHey;

  @override
  Widget build(BuildContext context) {
    final c = PlannerColors.of(context);
    Widget item(AppTab t, String label, {bool bump = false}) {
      final on = tab == t;
      return Expanded(
        child: Pressable(
          onTap: () => onTab(t),
          label: label,
          selected: on,
          pressedScale: 0.96,
          radius: 12,
          excludeChildSemantics: true,
          child: Container(
            height: 56,
            margin: const EdgeInsets.only(top: 6),
            alignment: Alignment.center,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Bump(
                on: bump,
                scale: 1.12,
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: PlannerType.ui(13, color: on ? c.tx : c.t3),
                  child: Text(label),
                ),
              ),
              const SizedBox(height: 6),
              _Bar(on: on, color: c.tx),
            ]),
          ),
        ),
      );
    }

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Primary',
      child: Container(
        height: kNavHeight,
        decoration: BoxDecoration(
          color: c.bg,
          border: Border(top: BorderSide(color: c.ln)),
        ),
        child: Stack(children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            item(AppTab.today, 'Today'),
            item(AppTab.plan, 'Plan', bump: planBump),
            const SizedBox(width: 92),
            item(AppTab.progress, 'Progress'),
            Expanded(
              child: Pressable(
                onTap: () => onTab(AppTab.settings),
                label: 'Settings',
                selected: tab == AppTab.settings,
                pressedScale: 0.92,
                radius: 12,
                excludeChildSemantics: true,
                child: Container(
                  height: 56,
                  margin: const EdgeInsets.only(top: 6),
                  alignment: Alignment.center,
                  child: PlannerIcon(PIcon.sliders,
                      size: 20, color: tab == AppTab.settings ? c.tx : c.t3),
                ),
              ),
            ),
          ]),
          Positioned(
            left: 0,
            right: 0,
            bottom: 12,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: showHey ? 1 : 0,
                duration: PlannerMotion.ms(context, 300),
                child: ExcludeSemantics(
                  child: Text('HEY PLANNER',
                      textAlign: TextAlign.center,
                      style: PlannerType.stateLabel(size: 9, tracking: 0.14, weight: 500, color: c.t3)),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.on, required this.color});
  final bool on;
  final Color color;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(end: on ? 1 : 0),
        duration: PlannerMotion.ms(context, 420),
        curve: const Cubic(0.34, 1.5, 0.55, 1),
        builder: (context, v, _) => Transform(
          alignment: Alignment.center,
          transform: Matrix4.diagonal3Values(v.clamp(0, 2), 1, 1),
          child: Container(
            width: 16,
            height: 2,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(1)),
          ),
        ),
      );
}
