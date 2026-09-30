import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/layout.dart';
import '../../app/state/ui_state.dart';
import '../../app/theme/planner_theme.dart';
import '../../data/settings.dart';
import 'dial_view.dart';
import 'timeline_strip.dart';
import 'today_header.dart';

class TodayPage extends ConsumerWidget {
  const TodayPage({super.key, this.compact = false, this.stripOnly = false});

  /// Rails on tablet and desktop: no view switch, strip only.
  final bool compact;
  final bool stripOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Tablet and desktop: Today is a rail beside the board, strip only.
    final wide = PlannerLayout.of(context).wide;
    final stripOnly = this.stripOnly || wide;
    final compact = this.compact || wide;
    final view = stripOnly ? TodayView.strip : ref.watch(todayUiProvider.select((u) => u.view));
    final sheetOpen = ref.watch(sheetProvider) != null;
    final strip = view == TodayView.strip;
    final ms = PlannerMotion.ms;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TodayHeader(compact: compact || stripOnly),
      const SizedBox(height: 4),
      Expanded(
        child: Stack(children: [
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !strip,
              child: AnimatedOpacity(
                opacity: strip ? 1 : 0,
                duration: ms(context, 300),
                child: AnimatedScale(
                  scale: strip ? 1 : 0.97,
                  duration: ms(context, 460),
                  curve: PlannerMotion.settleCurve,
                  child: TickerMode(
                    enabled: strip,
                    child: TimelineStrip(ambient: !sheetOpen),
                  ),
                ),
              ),
            ),
          ),
          if (!stripOnly)
            Positioned.fill(
              child: IgnorePointer(
                ignoring: strip,
                child: ExcludeSemantics(
                  excluding: strip,
                  child: AnimatedOpacity(
                    opacity: strip ? 0 : 1,
                    duration: ms(context, 300),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: strip ? 0 : 1),
                      duration: ms(context, 520),
                      curve: const Cubic(0.34, 1.25, 0.55, 1),
                      builder: (context, v, child) => Transform.rotate(
                        angle: (1 - v) * -8 * 3.14159265 / 180,
                        child: Transform.scale(scale: 0.9 + 0.1 * v, child: child),
                      ),
                      child: strip ? const SizedBox() : const DialView(),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      ),
    ]);
  }
}
