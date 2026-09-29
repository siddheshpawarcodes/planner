import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/state/actions.dart';
import '../../app/state/clock.dart';
import '../../app/state/derived.dart';
import '../../app/theme/planner_theme.dart';
import '../../domain/base_day.dart';
import '../../domain/scheduler.dart';
import '../../domain/task.dart';
import '../../domain/time.dart';
import '../../widgets/controls.dart';
import '../../widgets/planner_sheet.dart';
import '../../widgets/surfaces.dart';

/// DetailSheet (README 6.5).
class DetailSheet extends ConsumerStatefulWidget {
  const DetailSheet({super.key, required this.taskId});
  final String taskId;
  @override
  ConsumerState<DetailSheet> createState() => _DetailSheetState();
}

class _DetailSheetState extends ConsumerState<DetailSheet> {
  bool _delArm = false;
  Timer? _disarm;

  @override
  void dispose() {
    _disarm?.cancel();
    super.dispose();
  }

  void _delete(PlannerActions act) {
    if (!_delArm) {
      setState(() => _delArm = true);
      _disarm = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _delArm = false);
      });
      return;
    }
    act.deleteTask(widget.taskId);
  }

  @override
  Widget build(BuildContext context) {
    final c = PlannerColors.of(context);
    final act = ref.read(actionsProvider);
    final tasks = ref.watch(tasksProvider);
    final today = ref.watch(todayProvider);
    final now = ref.watch(nowMinuteProvider);
    final r = ref.watch(routineProvider);
    Task? tk;
    for (final t in tasks) {
      if (t.id == widget.taskId) tk = t;
    }
    if (tk == null || !tk.isScheduled) return const SizedBox(height: 120);
    final t = tk;
    final cat = t.cat;
    final miss = isMissed(t, today, now);
    final status = t.done
        ? 'Done at ${fmt(t.doneAt ?? t.end!)}'
        : t.skipped
            ? 'Skipped'
            : miss
                ? 'Missed'
                : t.day == today && now >= t.start!
                    ? 'In progress'
                    : 'Planned';
    final rows = [
      ('Deadline', t.deadline != null ? dayShort(t.deadline!) : 'None'),
      ('Priority', switch (t.priority) { Priority.high => 'High', Priority.low => 'Low', _ => 'Normal' }),
      ('Repeats', t.recurrence?.label ?? 'Never'),
      ('Added by', t.source == Source.voice ? 'Voice' : 'You'),
      ('Status', status),
    ];
    final same = stableSorted(
        tasks.where((x) => x.title == t.title && x.day != null && !x.deleted),
        (a, b) => a.day! - b.day!);
    final histText = same.length > 1
        ? 'Done ${same.where((x) => x.done).length} of the last ${same.length} times'
        : 'New on your plan. History builds as it repeats.';
    final seq = ref.watch(dayLayoutProvider(t.day!)).seq.where((x) => x.kind != ItemKind.marker).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        height: 36,
        child: Row(children: [
          CatSquare(cat.color, size: 10),
          const SizedBox(width: 8),
          Expanded(child: Text(cat.label, style: PlannerType.ui(13, color: c.t2))),
          const SheetClose(),
        ]),
      ),
      const SizedBox(height: 16),
      Semantics(
        header: true,
        child: Text(t.title, style: PlannerType.sheetTitle(color: c.tx).copyWith(letterSpacing: -0.6)),
      ),
      const SizedBox(height: 6),
      Wrap(spacing: 10, crossAxisAlignment: WrapCrossAlignment.end, children: [
        Text(dayShortMonth(t.day!), style: PlannerType.ui(14, weight: 400, color: c.t2)),
        Text('${fmt(t.start!)} → ${fmt(t.end!)}', style: PlannerType.time(size: 13, weight: 500, color: c.tx)),
        Text(dur(t.end! - t.start!), style: PlannerType.time(size: 13, color: c.t2)),
      ]),
      const SizedBox(height: 16),
      _MiniStrip(seq: seq, taskId: t.id, wake: r.wake, sleep: r.sleep),
      const SizedBox(height: 16),
      for (final (k, v) in rows)
        Container(
          constraints: const BoxConstraints(minHeight: 42),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: c.ln))),
          child: Row(children: [
            Expanded(child: Text(k, style: PlannerType.ui(14, weight: 400, color: c.t2))),
            Text(v, style: PlannerType.ui(14, weight: 400, color: c.tx)),
          ]),
        ),
      const SizedBox(height: 16),
      Text('History', style: PlannerType.ui(13, color: c.t2)),
      const SizedBox(height: 8),
      Semantics(
        label: histText,
        excludeSemantics: true,
        child: Wrap(spacing: 6, runSpacing: 6, children: [
          for (final x in same)
            Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: x.done ? cat.color : null,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                      color: x.done ? cat.color : x.skipped ? c.t3 : c.ln, width: 1.5),
                ),
                foregroundDecoration: x.id == t.id
                    ? BoxDecoration(
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                            color: c.tx, width: 1.5, strokeAlign: BorderSide.strokeAlignOutside + 2),
                      )
                    : null,
              ),
              const SizedBox(height: 4),
              Text(dayLetters[weekday0(x.day!)],
                  style: PlannerType.time(size: 9, weight: 500, color: c.t3)),
            ]),
        ]),
      ),
      const SizedBox(height: 8),
      Text(histText, style: PlannerType.ui(12.5, weight: 400, color: c.t3)),
      const SizedBox(height: 16),
      if (miss)
        PrimaryPill(
          label: 'Decide what to do with it',
          height: 52,
          expand: true,
          onTap: () => act.openDecision(t.id),
        )
      else
        PrimaryPill(
          label: t.done ? 'Mark not done' : 'Complete',
          height: 52,
          expand: true,
          background: cat.color,
          foreground: cat.ink,
          onTap: () => act.completeFromSheet(t.id),
        ),
      const SizedBox(height: 16),
      Row(children: [
        for (final (i, (label, onTap, col)) in [
          ('Reschedule', () => act.openDecision(t.id, reschedule: true), c.tx),
          ('Skip', () => act.skipTask(t.id), c.tx),
          ('Edit', () => act.openEdit(t.id), c.tx),
          (_delArm ? 'Tap again to delete' : 'Delete', () => _delete(act), _delArm ? Category.body.color : c.t2),
        ].indexed) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: Pressable(
              onTap: onTap,
              label: label,
              radius: 12,
              excludeChildSemantics: true,
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: c.s2, borderRadius: BorderRadius.circular(12)),
                child: Text(label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: PlannerType.ui(12.5, color: col).copyWith(height: 1.1)),
              ),
            ),
          ),
        ],
      ]),
    ]);
  }
}

/// Wake → sleep with this block highlighted among its neighbours.
class _MiniStrip extends StatelessWidget {
  const _MiniStrip({required this.seq, required this.taskId, required this.wake, required this.sleep});
  final List<TimelineItem> seq;
  final String taskId;
  final int wake, sleep;

  @override
  Widget build(BuildContext context) {
    final c = PlannerColors.of(context);
    return ExcludeSemantics(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: 14,
          child: LayoutBuilder(builder: (context, box) {
            final span = (sleep - wake).toDouble();
            return Stack(children: [
              for (final x in seq)
                Positioned(
                  left: (x.start - wake) / span * box.maxWidth,
                  width: ((x.end - x.start) / span * box.maxWidth - 1).clamp(1, box.maxWidth),
                  bottom: 0,
                  height: x.taskId == taskId ? 14 : 8,
                  child: switch (x.kind) {
                    ItemKind.protected => Hatch(color: c.t3, period: 4, radius: 2),
                    ItemKind.open => DashedBox(color: c.ln, radius: 2, dash: 3, gap: 2),
                    _ => DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(2),
                          color: x.taskId == taskId
                              ? x.cat!.color
                              : x.kind == ItemKind.task
                                  ? x.cat!.tintAt(c, 0.5)
                                  : x.kind == ItemKind.fixed
                                      ? (x.cat ?? Category.work).tintAt(c, 0.3)
                                      : Colors.transparent,
                        ),
                      ),
                  },
                ),
            ]);
          }),
        ),
        const SizedBox(height: 5),
        Row(children: [
          Text(fmt(wake), style: PlannerType.time(size: 10, weight: 500, color: c.t3)),
          const Spacer(),
          Text(fmt(sleep), style: PlannerType.time(size: 10, weight: 500, color: c.t3)),
        ]),
      ]),
    );
  }
}
