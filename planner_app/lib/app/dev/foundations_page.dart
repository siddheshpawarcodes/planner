import 'package:flutter/material.dart';

import '../theme/planner_theme.dart';

/// A live specimen of the Foundations board: grounds, category colours,
/// type and motion curves. Reachable from Settings › Developer in debug.
class FoundationsPage extends StatelessWidget {
  const FoundationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = PlannerColors.of(context);
    Widget swatch(String k, Color v) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            Container(
              width: 36,
              height: 24,
              decoration: BoxDecoration(
                color: v,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: c.ln),
              ),
            ),
            const SizedBox(width: 12),
            Text(k, style: PlannerType.time(color: c.t2)),
          ]),
        );
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('Planner foundations', style: PlannerType.screenTitle(color: c.tx)),
            const SizedBox(height: 20),
            for (final e in {
              'bg': c.bg,
              's1': c.s1,
              's2': c.s2,
              'ln': c.ln,
              'tx': c.tx,
              't2': c.t2,
              't3': c.t3,
            }.entries)
              swatch(e.key, e.value),
            const SizedBox(height: 16),
            for (final cat in Category.values)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                height: 44,
                child: Row(children: [
                  Expanded(
                    child: Container(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                          color: cat.color, borderRadius: BorderRadius.circular(4)),
                      child: Text(cat.label,
                          style: PlannerType.taskTitle(color: cat.ink)),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Container(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                          color: cat.tint(c), borderRadius: BorderRadius.circular(4)),
                      child: Text('${cat.label} tint',
                          style: PlannerType.taskTitle(color: c.tx)),
                    ),
                  ),
                ]),
              ),
            const SizedBox(height: 16),
            Text('Your week, as it happened.', style: PlannerType.display(color: c.tx)),
            const SizedBox(height: 8),
            Text('When do you wake up?', style: PlannerType.question(color: c.tx)),
            const SizedBox(height: 8),
            Text('Thursday 1 October', style: PlannerType.screenTitle(color: c.tx)),
            Text('07:00', style: PlannerType.numeral(88, color: c.tx)),
            Text('Tell Planner what you want to accomplish.',
                style: PlannerType.body(color: c.t2)),
            Text('20:00 → 22:00  2h', style: PlannerType.time(color: c.t3)),
            Text('NOW  NEXT  MISSED  LISTENING',
                style: PlannerType.stateLabel(color: c.tx)),
            const SizedBox(height: 16),
            for (final (n, curve, d) in [
              ('Snap 160', PlannerMotion.snapCurve, PlannerMotion.snap),
              ('Settle 420', PlannerMotion.settleCurve, PlannerMotion.settle),
              ('Spring 640', PlannerMotion.springCurve, PlannerMotion.spring),
            ])
              _CurveDot(label: n, curve: curve, duration: d),
          ],
        ),
      ),
    );
  }
}

class _CurveDot extends StatefulWidget {
  const _CurveDot({required this.label, required this.curve, required this.duration});
  final String label;
  final Curve curve;
  final Duration duration;
  @override
  State<_CurveDot> createState() => _CurveDotState();
}

class _CurveDotState extends State<_CurveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _a
      ..duration = PlannerMotion.of(context, widget.duration)
      ..repeat(reverse: true, period: PlannerMotion.of(context, widget.duration * 2));
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = PlannerColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        SizedBox(width: 96, child: Text(widget.label, style: PlannerType.time(color: c.t2))),
        Expanded(
          child: LayoutBuilder(builder: (context, box) {
            return AnimatedBuilder(
              animation: _a,
              builder: (context, _) => Stack(children: [
                Container(height: 12, color: Colors.transparent),
                Positioned(
                  top: 5,
                  left: 0,
                  right: 0,
                  child: Container(height: 2, color: c.s1),
                ),
                Positioned(
                  left: widget.curve.transform(_a.value) * (box.maxWidth - 12),
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(color: c.tx, shape: BoxShape.circle),
                  ),
                ),
              ]),
            );
          }),
        ),
      ]),
    );
  }
}
