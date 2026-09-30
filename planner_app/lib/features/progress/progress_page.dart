import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/state/actions.dart';
import '../../app/state/clock.dart';
import '../../app/state/derived.dart';
import '../../app/state/ui_state.dart';
import '../../app/theme/planner_theme.dart';
import '../../domain/progress.dart';
import '../../domain/time.dart';
import '../../widgets/controls.dart';
import 'heatmap.dart';
import 'ribbon.dart';

/// Progress (README 6.8): the category ribbon, the done count, three stats,
/// the moved cells, the focus heatmap and the weekly review entry. Every
/// visit replays the reveal: ribbon left to right (1400 Settle), counters
/// (1500 ease-out cubic) and the heatmap's diagonal entry.
class ProgressPage extends ConsumerStatefulWidget {
  const ProgressPage({super.key});

  @override
  ConsumerState<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends ConsumerState<ProgressPage> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
  bool _withWork = false;
  int? _day;
  (int, int)? _cell;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(currentTabProvider) == AppTab.progress) _replay();
    });
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  void _replay() {
    setState(() {
      _day = null;
      _cell = null;
    });
    _a.duration = PlannerMotion.ms(context, 1500);
    _a.value = 0;
    Future.delayed(PlannerMotion.ms(context, 60), () {
      if (mounted) _a.forward(from: 0);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(currentTabProvider, (prev, next) {
      if (next == AppTab.progress && prev != AppTab.progress) _replay();
    });
    final c = PlannerColors.of(context);
    final p = ref.watch(weekProgressProvider);
    final today = ref.watch(todayProvider);
    final canReview = ref.watch(reviewAvailableProvider);
    return AnimatedBuilder(
      animation: _a,
      builder: (context, _) {
        final v = _a.value;
        final reveal = PlannerMotion.settleCurve.transform((v * 1500 / 1400).clamp(0.0, 1.0));
        final pk = 1 - (1 - v) * (1 - v) * (1 - v);
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
          children: [
            _header(c, today),
            const SizedBox(height: 26),
            CategoryRibbon(
              progress: p,
              withWork: _withWork,
              selected: _day,
              reveal: reveal,
              onSelect: (d) => setState(() => _day = _day == d ? null : d),
            ),
            const SizedBox(height: 10),
            _dayLabels(c, p),
            const SizedBox(height: 10),
            _legend(c, p, canReview),
            const SizedBox(height: 26),
            _hero(c, p, pk, canReview),
            const SizedBox(height: 26),
            _stats(c, p, pk),
            const SizedBox(height: 26),
            _moved(c, p, pk),
            const SizedBox(height: 26),
            _heat(c, p, v * 1500),
            const SizedBox(height: 26),
            if (canReview)
              PrimaryPill(
                label: 'Review this week',
                height: 52,
                expand: true,
                onTap: ref.read(actionsProvider).openReview,
              )
            else
              Text('The weekly review opens on Sunday evening.',
                  textAlign: TextAlign.center, style: PlannerType.body(size: 13, color: c.t3)),
          ],
        );
      },
    );
  }

  Widget _header(PlannerColors c, int today) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(children: [
          Expanded(
            child: Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: 10, children: [
              Semantics(header: true, child: Text('This week', style: PlannerType.screenTitle(color: c.tx))),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(weekRange(today), style: PlannerType.time(size: 12, color: c.t3)),
              ),
            ]),
          ),
          SegmentedPill<bool>(
            options: const [(false, 'Your time'), (true, 'With work')],
            value: _withWork,
            onChanged: (v) => setState(() => _withWork = v),
            width: 168,
            height: 32,
            outlined: true,
            fontSize: 12,
            label: 'Ribbon shows',
          ),
        ]),
      );

  Widget _dayLabels(PlannerColors c, WeekProgress p) => LayoutBuilder(
        builder: (context, box) => SizedBox(
          // Two mono lines; grows with the text size.
          height: MediaQuery.textScalerOf(context).scale(11) * 1.2 +
              MediaQuery.textScalerOf(context).scale(10) * 1.2 +
              6,
          child: Stack(children: [
            for (var d = 0; d < 7; d++)
              Positioned(
                left: ribbonX(d, box.maxWidth) - 22,
                width: 44,
                top: 0,
                bottom: 0,
                child: ExcludeSemantics(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _day = _day == d ? null : d),
                    child: Column(children: [
                      Text(dayLetters[d],
                          style: PlannerType.time(
                                  size: 11, weight: _day == d ? 600 : 500, color: _day == d ? c.tx : c.t3)
                              .copyWith(height: 1.2)),
                      const SizedBox(height: 1),
                      Text('${dayNumber(p.weekStart + d)}',
                          style: PlannerType.time(size: 10, color: c.t3).copyWith(height: 1.2)),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
      );

  Widget _legend(PlannerColors c, WeekProgress p, bool weekDone) {
    final d = _day;
    final String head;
    final List<(Category, int)> rows;
    if (d == null) {
      head = weekDone ? 'Where your week went' : 'Where your week is going';
      rows = p.totals(withWork: _withWork);
    } else {
      head = p.beforePlanner(d) ? '${dayLongNames[d]}, before Planner' : '${dayLongNames[d]}, ${dur(p.dayTotal(d, withWork: _withWork))}';
      rows = p.dayBreakdown(d, withWork: _withWork);
    }
    return Semantics(
      liveRegion: d != null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(head, style: PlannerType.bricolage600(15, color: c.tx)),
        const SizedBox(height: 8),
        if (rows.isEmpty)
          Text('Nothing tracked on this day.', style: PlannerType.body(size: 13, color: c.t3))
        else
          LayoutBuilder(builder: (context, box) {
            final w = (box.maxWidth - 18) / 2;
            return Wrap(spacing: 18, runSpacing: 6, children: [
              for (final (cat, m) in rows)
                SizedBox(
                  width: w,
                  child: Row(children: [
                    CatSquare(cat.color, size: 8),
                    const SizedBox(width: 8),
                    Expanded(child: Text(cat.label, style: PlannerType.body(size: 13, color: c.tx))),
                    Text(dur(m), style: PlannerType.time(size: 12, color: c.t2)),
                  ]),
                ),
            ]);
          }),
      ]),
    );
  }

  Widget _hero(PlannerColors c, WeekProgress p, double pk, bool weekDone) {
    final has = p.plannedCount > 0;
    return Semantics(
      label: has ? '${p.doneCount} of ${p.plannedCount} planned tasks done' : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (has)
          ExcludeSemantics(
            child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              Text('${(p.doneCount * pk).round()}', style: PlannerType.numeral(64, color: c.tx)),
              const SizedBox(width: 10),
              Text('of ${p.plannedCount}', style: PlannerType.numeral(26, color: c.t2).copyWith(letterSpacing: 0)),
            ]),
          ),
        if (has) const SizedBox(height: 6),
        ExcludeSemantics(
          excluding: has,
          child: Text(has ? 'planned tasks done' : 'Your first week has started.',
              style: PlannerType.bricolage600(17, color: c.tx)),
        ),
        const SizedBox(height: 6),
        Text(progressSubline(p, weekDone: weekDone), style: PlannerType.body(size: 13, color: c.t2)),
      ]),
    );
  }

  Widget _stats(PlannerColors c, WeekProgress p, double pk) {
    Widget stat(String v, String label, {bool rule = true}) => Expanded(
          child: Semantics(
            label: '$v $label',
            excludeSemantics: true,
            child: Container(
              padding: EdgeInsets.only(left: rule ? 14 : 0),
              decoration: rule ? BoxDecoration(border: Border(left: BorderSide(color: c.ln))) : null,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(v,
                    maxLines: 1,
                    style: PlannerType.ui(22, weight: 400, color: c.tx, tracking: -0.02)
                        .copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                const SizedBox(height: 3),
                Text(label, style: PlannerType.ui(12, weight: 400, color: c.t3)),
              ]),
            ),
          ),
        );
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        stat('${(p.percent * pk).round()}%', 'completed', rule: false),
        stat(dur(p.focusedMinutes * pk), 'focused'),
        stat('${(p.daysWithPlanner * pk).round()}', 'days with Planner'),
      ]),
    );
  }

  Widget _moved(PlannerColors c, WeekProgress p, double pk) => Row(children: [
        for (final (i, (k, n)) in [
          ('Rescheduled', p.rescheduled.length),
          ('Skipped', p.skipped.length),
          ('Carried forward', p.carried.length),
        ].indexed) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Semantics(
              label: '$k $n',
              excludeSemantics: true,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: c.s1, borderRadius: BorderRadius.circular(4)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${(n * pk).round()}', style: PlannerType.ui(20, weight: 400, color: c.tx)),
                  const SizedBox(height: 2),
                  Text(k, maxLines: 1, overflow: TextOverflow.ellipsis, style: PlannerType.ui(12, weight: 400, color: c.t2)),
                ]),
              ),
            ),
          ),
        ],
      ]);

  Widget _heat(PlannerColors c, WeekProgress p, double t) {
    final info = _cell != null ? heatCellText(p, _cell!.$1, _cell!.$2) : heatSummary(p);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('When you actually work', style: PlannerType.bricolage600(15, color: c.tx)),
      const SizedBox(height: 3),
      ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 17),
        child: Semantics(liveRegion: true, child: Text(info, style: PlannerType.body(size: 13, color: c.t2))),
      ),
      const SizedBox(height: 12),
      FocusHeatmap(
        progress: p,
        t: t,
        selected: _cell,
        onSelect: (r, col) => setState(() => _cell = (r, col)),
      ),
    ]);
  }
}
