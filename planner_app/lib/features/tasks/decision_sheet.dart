import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/state/actions.dart';
import '../../app/state/clock.dart';
import '../../app/state/derived.dart';
import '../../app/theme/planner_theme.dart';
import '../../domain/scheduler.dart';
import '../../domain/task.dart';
import '../../domain/time.dart';
import '../../widgets/controls.dart';
import '../../widgets/icons.dart';
import '../../widgets/planner_sheet.dart';

/// DecisionSheet (README 6.6): the missed task, or Detail's Reschedule.
/// Every option shows the scheduler's real answer on the right.
class DecisionSheet extends ConsumerStatefulWidget {
  const DecisionSheet({super.key, required this.taskId, required this.reschedule});
  final String taskId;
  final bool reschedule;

  @override
  ConsumerState<DecisionSheet> createState() => _DecisionSheetState();
}

class _DecisionSheetState extends ConsumerState<DecisionSheet> {
  bool _pick = false, _delArm = false;
  Timer? _disarm;

  @override
  void dispose() {
    _disarm?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = PlannerColors.of(context);
    final act = ref.read(actionsProvider);
    final tasks = ref.watch(tasksProvider);
    final r = ref.watch(routineProvider);
    final today = ref.watch(todayProvider);
    final now = ref.watch(nowMinuteProvider);
    Task? t;
    for (final x in tasks) {
      if (x.id == widget.taskId) t = x;
    }
    if (t == null || !t.isScheduled) return const SizedBox(height: 120);
    final task = t;
    final opts = rescheduleOptions(task, r, tasks, today: today, now: now);
    final days = chooseDaySlots(task, r, tasks, today: today, now: now);

    Widget row(String label, {String? value, VoidCallback? onTap, bool enabled = true, Color? color, Widget? trailing}) =>
        SheetRow(
          label: label,
          value: value,
          onTap: onTap ?? () {},
          enabled: enabled,
          color: color,
          trailing: trailing,
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Semantics(
                header: true,
                child: Text(
                    widget.reschedule ? 'When should this happen?' : 'What should we do with this?',
                    style: PlannerType.bricolage600(26, height: 1.1, tracking: -0.015, color: c.tx)),
              ),
              const SizedBox(height: 6),
              Text(
                  '${task.title} was planned for ${dayShortNames[weekday0(task.day!)]} ${fmt(task.start!)} → ${fmt(task.end!)}.',
                  style: PlannerType.body(size: 13.5, color: c.t2)),
            ]),
          ),
        ),
        const SheetClose(),
      ]),
      const SizedBox(height: 14),
      for (final o in opts)
        row(o.label,
            value: o.text,
            enabled: o.ok,
            onTap: o.ok ? () => act.reschedTo(task.id, o.day, o.slot!) : null),
      row('Choose a day',
          onTap: () => setState(() => _pick = !_pick),
          trailing: AnimatedRotation(
            turns: _pick ? 0.25 : 0,
            duration: PlannerMotion.ms(context, 300),
            child: PlannerIcon(PIcon.chev, size: 16, color: c.t3),
          )),
      AnimatedSize(
        duration: PlannerMotion.ms(context, 420),
        curve: PlannerMotion.settleCurve,
        child: !_pick
            ? const SizedBox(width: double.infinity)
            : Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 12),
                child: Row(children: [
                  for (final (i, (d, sl)) in days.indexed) ...[
                    if (i > 0) const SizedBox(width: 4),
                    Expanded(
                      child: Pressable(
                        onTap: sl == null ? null : () => act.reschedTo(task.id, d, sl),
                        label: '${dayLongNames[weekday0(d)]} ${dayNumber(d)}, ${sl == null ? 'full' : fmt(sl.start)}',
                        radius: 10,
                        excludeChildSemantics: true,
                        child: Container(
                          height: 64,
                          decoration: BoxDecoration(
                            color: c.bg,
                            border: Border.all(color: c.ln),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Text(dayShortNames[weekday0(d)],
                                style: PlannerType.time(size: 10, weight: 500, color: c.t3)),
                            const SizedBox(height: 2),
                            Text('${dayNumber(d)}',
                                style: PlannerType.ui(15, color: sl == null ? c.t3 : c.tx)),
                            const SizedBox(height: 2),
                            Text(sl == null ? 'Full' : fmt(sl.start),
                                style: PlannerType.time(size: 9.5, color: c.t2)),
                          ]),
                        ),
                      ),
                    ),
                  ],
                ]),
              ),
      ),
      row(task.recurrence != null ? 'Skip this occurrence' : 'Skip this time',
          onTap: () => act.skipTask(task.id),
          trailing: Text('Counts as a decision', style: PlannerType.ui(12, weight: 400, color: c.t3))),
      row(_delArm ? 'Tap again to delete' : 'Delete',
          color: _delArm ? Category.body.color : c.t2,
          onTap: () {
            if (_delArm) {
              act.deleteTask(task.id);
              return;
            }
            setState(() => _delArm = true);
            _disarm = Timer(const Duration(seconds: 4), () {
              if (mounted) setState(() => _delArm = false);
            });
          }),
    ]);
  }
}
