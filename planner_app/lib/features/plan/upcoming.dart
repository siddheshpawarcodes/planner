import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/state/clock.dart';
import '../../app/state/derived.dart';
import '../../app/theme/planner_theme.dart';
import '../../domain/task.dart';
import '../../domain/time.dart';
import '../../widgets/controls.dart';
import 'plan_page.dart';

/// Plan › Upcoming: Deadlines, Repeats and Unscheduled.
class UpcomingList extends ConsumerWidget {
  const UpcomingList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = PlannerColors.of(context);
    final today = ref.watch(todayProvider);
    final tasks = ref.watch(tasksProvider);
    final r = ref.watch(routineProvider);
    final series = ref.watch(seriesProvider);
    final dls = stableSorted(ref.watch(deadlinesProvider).where((d) => d.day >= today),
        (a, b) => a.day - b.day);
    final commits = r.commitments.where((x) => x.on).toList();
    final inbox = tasks.where((t) => t.day == null && !t.deleted).toList();

    String noteFor(Deadline d) {
      if (d.note != null) return d.note!;
      final n = tasks
          .where((t) => t.isLive && !t.done && t.cat == d.cat && t.day! >= today && t.day! <= d.day)
          .length;
      if (n == 0) return d.minute != null ? 'Due ${fmt(d.minute!)}' : 'Nothing planned for it yet';
      return '$n ${d.cat.label.toLowerCase()} ${n > 1 ? 'blocks' : 'block'} planned before it';
    }

    String inDays(int d) => d == today
        ? 'Today'
        : d == today + 1
            ? 'Tomorrow'
            : 'In ${d - today} days';

    Widget heading(String t) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Semantics(header: true, child: Text(t, style: PlannerType.bricolage600(16, color: c.tx))),
        );
    Widget hair(Widget child) => Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: c.ln))),
          child: child,
        );

    final empty = dls.isEmpty && commits.isEmpty && series.isEmpty && inbox.isEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (dls.isNotEmpty) ...[
        heading('Deadlines'),
        for (final d in dls)
          hair(Row(children: [
            CatSquare(d.cat.color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(d.title, style: PlannerType.bricolage600(15, color: c.tx)),
                const SizedBox(height: 2),
                Text(noteFor(d), style: PlannerType.ui(12, weight: 400, color: c.t2)),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(dayShortMonth(d.day), style: PlannerType.time(size: 12, weight: 500, color: c.tx)),
              const SizedBox(height: 2),
              Text(inDays(d.day), style: PlannerType.ui(11, weight: 400, color: c.t3)),
            ]),
          ])),
        const SizedBox(height: 26),
      ],
      if (commits.isNotEmpty || series.isNotEmpty) ...[
        heading('Repeats'),
        for (final x in commits)
          hair(Row(children: [
            CatSquare(x.cat.color),
            const SizedBox(width: 12),
            Expanded(child: Text(x.title, style: PlannerType.bricolage600(15, color: c.tx))),
            Text(x.label, style: PlannerType.time(size: 12, color: c.t2)),
          ])),
        for (final s in series)
          hair(Row(children: [
            CatSquare(s.cat.color),
            const SizedBox(width: 12),
            Expanded(child: Text(s.title, style: PlannerType.bricolage600(15, color: c.tx))),
            Flexible(
              child: Text('${s.rule.label}, ${fmt(s.start)} → ${fmt(s.end)}',
                  textAlign: TextAlign.right, style: PlannerType.time(size: 12, color: c.t2)),
            ),
          ])),
        const SizedBox(height: 26),
      ],
      heading('Unscheduled'),
      const InboxList(),
      if (empty) ...[
        const SizedBox(height: 16),
        Text('Nothing upcoming. Your week is clear.', style: PlannerType.ui(13, weight: 400, color: c.t2)),
      ],
    ]);
  }
}
