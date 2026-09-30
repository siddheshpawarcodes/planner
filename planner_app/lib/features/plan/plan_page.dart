import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/layout.dart';
import '../../app/state/actions.dart';
import '../../app/state/clock.dart';
import '../../app/state/derived.dart';
import '../../app/state/staging.dart';
import '../../app/state/ui_state.dart';
import '../../app/theme/planner_theme.dart';
import '../../domain/capacity.dart';
import '../../domain/task.dart';
import '../../domain/time.dart';
import '../../widgets/controls.dart';
import '../../widgets/icons.dart';
import 'plan_board.dart';
import 'upcoming.dart';

/// Plan (README 6.7): one board at three zooms, plus Upcoming.
class PlanPage extends ConsumerWidget {
  const PlanPage({super.key, this.allExpanded = false, this.showHeader = true});

  /// Desktop: the week planner with every day expanded.
  final bool allExpanded;
  final bool showHeader;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = PlannerColors.of(context);
    final ui = ref.watch(planUiProvider);
    final today = ref.watch(todayProvider);
    final act = ref.read(actionsProvider);
    final sel = switch (ui.seg) {
      PlanSeg.today => today,
      PlanSeg.tomorrow => today + 1,
      _ => ui.weekSel ?? today,
    };
    final up = ui.seg == PlanSeg.upcoming;
    // Desktop: the week planner shows all seven days expanded.
    final allExpanded =
        this.allExpanded || (PlannerLayout.of(context) == LayoutKind.desktop && ui.seg == PlanSeg.week);
    final title = switch (ui.seg) {
      PlanSeg.week => 'This week',
      PlanSeg.upcoming => 'Upcoming',
      _ => dayLabel(sel),
    };
    final ms = PlannerMotion.ms;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
      children: [
        if (showHeader)
          SizedBox(
            height: 44,
            child: Row(children: [
              const SizedBox(width: 4),
              Expanded(
                child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                  Flexible(
                    child: Semantics(
                      header: true,
                      child: Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PlannerType.screenTitle(color: c.tx)),
                    ),
                  ),
                  if (ui.seg == PlanSeg.week) ...[
                    const SizedBox(width: 10),
                    Text(weekRange(sel), style: PlannerType.time(size: 12, color: c.t3)),
                  ],
                ]),
              ),
              PlannerIconButton(
                icon: PIcon.plus,
                label: 'Add task',
                onTap: () => act.openCreate(date: up ? null : sel),
              ),
            ]),
          ),
        const SizedBox(height: 12),
        SegmentedPill<PlanSeg>(
          label: 'Plan view',
          height: 40,
          options: const [
            (PlanSeg.today, 'Today'),
            (PlanSeg.tomorrow, 'Tomorrow'),
            (PlanSeg.week, 'Week'),
            (PlanSeg.upcoming, 'Upcoming'),
          ],
          value: ui.seg,
          onChanged: act.setSeg,
        ),
        const SizedBox(height: 12),
        AnimatedCrossFade(
          duration: ms(context, 320),
          sizeCurve: PlannerMotion.settleCurve,
          crossFadeState: up ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          firstChild: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            PlanBoard(
              sel: sel,
              week: ui.seg == PlanSeg.week || allExpanded,
              allExpanded: allExpanded,
            ),
            const SizedBox(height: 4),
            _DaySummary(sel: sel, dayMode: ui.seg == PlanSeg.today || ui.seg == PlanSeg.tomorrow),
          ]),
          secondChild: const Padding(
            padding: EdgeInsets.only(top: 6),
            child: UpcomingList(),
          ),
        ),
      ],
    );
  }
}

/// Below the board: the selected day, its load, the overload row, and (in
/// the day zooms) the Unscheduled inbox.
class _DaySummary extends ConsumerWidget {
  const _DaySummary({required this.sel, required this.dayMode});
  final int sel;
  final bool dayMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = PlannerColors.of(context);
    final r = ref.watch(routineProvider);
    final tasks = ref.watch(effectiveTasksProvider);
    final today = ref.watch(todayProvider);
    final ack = ref.watch(stagingProvider.select((s) => s.overAckWeek));
    final act = ref.read(actionsProvider);
    final cap = capOf(sel, r, tasks, 0,
        weekendCap: learnedWeekendCap(sel, tasks, historyDays: ref.watch(historyDaysProvider)));
    final tot = cap.planned + cap.done;
    final showOver = cap.isOver && !ack.contains(sel) && sel >= today;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(dayLabel(sel), style: PlannerType.bricolage600(16, color: c.tx)),
              const SizedBox(height: 2),
              Text('${dur(tot)} planned of ${dur(cap.realistic)} realistic',
                  style: PlannerType.ui(12, weight: 400, color: c.t2)),
            ]),
          ),
          SecondaryPill(label: 'Add to this day', height: 40, padding: 14, onTap: () => act.openCreate(date: sel)),
        ]),
        if (showOver) ...[
          const SizedBox(height: 10),
          CalmRow(
            actions: [
              PrimaryPill(label: 'Move one', padding: 14, onTap: () => act.moveOneFrom(sel)),
              TextPill(label: 'Keep', onTap: () => act.keepWeek(sel)),
            ],
            child: Text(
                '${dayLongNames[weekday0(sel)]} runs ${dur(cap.over)} past what fits. Move one block to a lighter day?',
                style: PlannerType.body(size: 12.5, color: c.tx).copyWith(height: 1.35)),
          ),
        ],
        if (dayMode) ...[
          const SizedBox(height: 14),
          Text('Unscheduled', style: PlannerType.ui(13, color: c.t2)),
          const SizedBox(height: 8),
          const InboxList(boxed: true),
        ],
      ]),
    );
  }
}

/// Unscheduled tasks with Fit in.
class InboxList extends ConsumerWidget {
  const InboxList({super.key, this.boxed = false});

  /// Boxed rows (day zooms) vs hairline rows (Upcoming).
  final bool boxed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = PlannerColors.of(context);
    final inbox = [
      for (final t in ref.watch(tasksProvider))
        if (t.day == null && !t.deleted) t
    ];
    final act = ref.read(actionsProvider);
    if (inbox.isEmpty) {
      return Container(
        padding: EdgeInsets.symmetric(vertical: boxed ? 0 : 12),
        decoration: boxed ? null : BoxDecoration(border: Border(top: BorderSide(color: c.ln))),
        child: Text('Nothing waiting. Tasks without a time land here.',
            style: PlannerType.ui(boxed ? 12.5 : 13, weight: 400, color: c.t3)),
      );
    }
    Widget row(Task t) => Container(
          margin: EdgeInsets.only(bottom: boxed ? 8 : 0),
          constraints: BoxConstraints(minHeight: boxed ? 48 : 56),
          padding: EdgeInsets.fromLTRB(boxed ? 12 : 0, 4, boxed ? 6 : 0, 4),
          decoration: boxed
              ? BoxDecoration(color: c.s1, borderRadius: BorderRadius.circular(4))
              : BoxDecoration(border: Border(top: BorderSide(color: c.ln))),
          child: Row(children: [
            CatSquare(t.cat.color),
            SizedBox(width: boxed ? 10 : 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PlannerType.bricolage600(boxed ? 14 : 15, color: c.tx)),
                Text(dur(t.duration), style: PlannerType.time(size: 11, color: c.t3)),
              ]),
            ),
            Semantics(
              label: 'Fit ${t.title} into the next free slot',
              excludeSemantics: true,
              child: PrimaryPill(label: 'Fit in', height: 36, padding: 12, onTap: () => act.fitIn(t.id)),
            ),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (final t in inbox) row(t)]);
  }
}
