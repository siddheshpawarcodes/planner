import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/theme/planner_theme.dart';
import '../../domain/progress.dart';
import '../../domain/time.dart';

/// `FocusHeatmap`: 7 × 36 half-hour cells (06:00 → 24:00) in monochrome
/// `tx` at 0 / .18 / .36 / .62 / 1. Cells enter on a diagonal ([stagger] ms
/// per row plus column); [t] is milliseconds since the entry began. A
/// bracket marks the best window.
class FocusHeatmap extends StatelessWidget {
  const FocusHeatmap({
    super.key,
    required this.progress,
    required this.t,
    this.rows = const [0, 1, 2, 3, 4, 5, 6],
    this.cellHeight = 14,
    this.stagger = 11,
    this.labels = true,
    this.bracket = true,
    this.selected,
    this.onSelect,
  });

  final WeekProgress progress;
  final double t;
  final List<int> rows;
  final double cellHeight;
  final int stagger;
  final bool labels, bracket;
  final (int, int)? selected;
  final void Function(int row, int cell)? onSelect;

  static const _entryCurve = Cubic(0.34, 1.5, 0.55, 1);

  @override
  Widget build(BuildContext context) {
    final c = PlannerColors.of(context);
    final p = progress;
    final best = p.best;
    final showBracket = bracket && best != null && p.daysWithPlanner >= 3;
    final gutter = labels ? 20.0 : 0.0;
    final rowGap = 3.0;
    final gridH = rows.length * cellHeight + (rows.length - 1) * rowGap;
    Widget grid(double w) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: onSelect == null
              ? null
              : (d) {
                  final cw = (w + 2) / kHeatCells;
                  final col = (d.localPosition.dx / cw).floor().clamp(0, kHeatCells - 1);
                  final r = (d.localPosition.dy / (cellHeight + rowGap)).floor().clamp(0, rows.length - 1);
                  onSelect!(rows[r], col);
                },
          child: CustomPaint(
            size: Size(w, gridH),
            painter: _HeatPainter(p, rows, t, cellHeight, rowGap, stagger, selected, c.tx, c.s1),
          ),
        );
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth - gutter;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        if (bracket)
          Padding(
            padding: EdgeInsets.only(left: gutter),
            child: SizedBox(
              height: 10,
              child: Stack(children: [
                if (best != null)
                  Positioned(
                    left: best.cell / kHeatCells * w,
                    width: 4 / kHeatCells * w,
                    top: 2,
                    height: 6,
                    child: Opacity(
                      opacity: showBracket ? ((t - 700) / 400).clamp(0.0, 1.0) : 0,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(color: c.tx, width: 1.5),
                            left: BorderSide(color: c.tx, width: 1.5),
                            right: BorderSide(color: c.tx, width: 1.5),
                          ),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        if (bracket) const SizedBox(height: 3),
        Semantics(
          label: _summary(p),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (labels)
              SizedBox(
                width: gutter,
                child: Column(children: [
                  for (final (i, r) in rows.indexed) ...[
                    if (i > 0) SizedBox(height: rowGap),
                    SizedBox(
                      height: cellHeight,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(dayLetters[r], style: PlannerType.time(size: 10, weight: 500, color: c.t3)),
                      ),
                    ),
                  ],
                ]),
              ),
            ExcludeSemantics(child: grid(w)),
          ]),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: EdgeInsets.only(left: gutter),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            for (final h in const ['06', '12', '18', '24'])
              Text(h, style: PlannerType.time(size: 10, weight: 500, color: c.t3)),
          ]),
        ),
      ]);
    });
  }

  /// Row summaries for screen readers.
  String _summary(WeekProgress p) {
    final parts = <String>[];
    for (final r in rows) {
      final m = p.heat[r].fold(0, (a, v) => a + v);
      if (m > 0) parts.add('${dayLongNames[r]} ${dur(m)} focused');
    }
    return parts.isEmpty ? 'When you actually work: nothing tracked yet' : 'When you actually work. ${parts.join(', ')}';
  }
}

class _HeatPainter extends CustomPainter {
  _HeatPainter(this.p, this.rows, this.t, this.h, this.gap, this.stagger, this.sel, this.tx, this.s1);
  final WeekProgress p;
  final List<int> rows;
  final double t, h, gap;
  final int stagger;
  final (int, int)? sel;
  final Color tx, s1;

  @override
  void paint(Canvas canvas, Size size) {
    final cw = (size.width + 2) / kHeatCells - 2;
    final fill = Paint();
    for (final (i, r) in rows.indexed) {
      for (var col = 0; col < kHeatCells; col++) {
        final delay = (r + col) * stagger;
        final e = ((t - delay) / 360).clamp(0.0, 1.0);
        if (e <= 0) continue;
        final s = 0.3 + 0.7 * FocusHeatmap._entryCurve.transform(((t - delay) / 520).clamp(0.0, 1.0));
        final lv = heatLevel(p.heat[r][col]);
        final rect = Rect.fromLTWH(col * (cw + 2), i * (h + gap), cw, h);
        final scaled = Rect.fromCenter(center: rect.center, width: rect.width * s, height: rect.height * s);
        fill.color = lv > 0 ? tx.withValues(alpha: heatOpacity[lv] * e) : s1.withValues(alpha: e);
        final rr = RRect.fromRectAndRadius(scaled, const Radius.circular(2));
        canvas.drawRRect(rr, fill);
        if (sel == (r, col)) {
          canvas.drawRRect(
              rr.inflate(0.75),
              Paint()
                ..color = tx
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.5);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_HeatPainter old) =>
      old.t != t || old.p != p || old.sel != sel || old.tx != tx || old.s1 != s1 || !listEquals(old.rows, rows);
}

/// Total milliseconds a heatmap entry takes.
double heatEntryMs(int stagger) => (6 + kHeatCells - 1) * stagger + 520.0;
