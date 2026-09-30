import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../../app/theme/planner_theme.dart';
import '../../domain/progress.dart';
import '../../domain/time.dart';

/// Band geometry: seven top and bottom y values per category, plus the
/// dashed envelope. Every category is always present (zero thickness when
/// hidden) so any two geometries lerp point by point.
class RibbonGeometry {
  const RibbonGeometry(this.tops, this.bottoms, this.opacity, this.envTop, this.envBottom);

  final Map<Category, List<double>> tops, bottoms;
  final Map<Category, double> opacity;
  final List<double> envTop, envBottom;

  static const height = 196.0, mid = 98.0;

  /// Prototype `V.ribbon`: bands stacked on a centred baseline, 170px for
  /// the largest day (completed or planned).
  factory RibbonGeometry.of(WeekProgress p, {required bool withWork, int? selected}) {
    final cats = p.cats(withWork: withWork);
    final tot = [for (var d = 0; d < 7; d++) p.dayTotal(d, withWork: withWork)];
    final env = [for (var d = 0; d < 7; d++) p.envelope(d, withWork: withWork)];
    final maxE = [60, ...tot, ...env].reduce(math.max);
    final rs = 170 / maxE;
    final cursor = [for (final v in tot) mid - v * rs / 2];
    final tops = <Category, List<double>>{}, bottoms = <Category, List<double>>{};
    final op = <Category, double>{};
    for (final c in ribbonOrder) {
      final on = cats.contains(c);
      final t = <double>[], b = <double>[];
      for (var d = 0; d < 7; d++) {
        final y0 = cursor[d], y1 = y0 + (on ? p.completed[c]![d] * rs : 0);
        t.add(y0);
        b.add(y1);
        cursor[d] = y1;
      }
      tops[c] = t;
      bottoms[c] = b;
      op[c] = selected == null || p.completed[c]![selected] > 0 ? 0.94 : 0.35;
    }
    return RibbonGeometry(tops, bottoms, op, [for (final e in env) mid - e * rs / 2],
        [for (final e in env) mid + e * rs / 2]);
  }

  static RibbonGeometry lerp(RibbonGeometry a, RibbonGeometry b, double t) {
    List<double> l(List<double> x, List<double> y) => [for (var i = 0; i < 7; i++) lerpDouble(x[i], y[i], t)!];
    return RibbonGeometry(
      {for (final c in ribbonOrder) c: l(a.tops[c]!, b.tops[c]!)},
      {for (final c in ribbonOrder) c: l(a.bottoms[c]!, b.bottoms[c]!)},
      {for (final c in ribbonOrder) c: lerpDouble(a.opacity[c], b.opacity[c], t)!},
      l(a.envTop, b.envTop),
      l(a.envBottom, b.envBottom),
    );
  }
}

/// x of day [d] in a ribbon [w] wide (prototype `xs`: 14 + d × 332/6 at 360).
double ribbonX(int d, double w) => 14 + d * (w - 28) / 6;

/// `CategoryRibbon`: the stacked streamgraph (README 6.8). Horizontal-tangent
/// cubics, 1px `bg` separators, a dashed envelope for what was planned, and
/// a left-to-right reveal ([reveal] 0..1). Tapping a day selects it.
class CategoryRibbon extends StatefulWidget {
  const CategoryRibbon({
    super.key,
    required this.progress,
    required this.withWork,
    this.selected,
    this.onSelect,
    this.reveal = 1,
  });

  final WeekProgress progress;
  final bool withWork;
  final int? selected;
  final ValueChanged<int>? onSelect;
  final double reveal;

  @override
  State<CategoryRibbon> createState() => _CategoryRibbonState();
}

class _CategoryRibbonState extends State<CategoryRibbon> with SingleTickerProviderStateMixin {
  late final AnimationController _morph =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 620), value: 1);
  late RibbonGeometry _from = _target, _to = _target;

  RibbonGeometry get _target =>
      RibbonGeometry.of(widget.progress, withWork: widget.withWork, selected: widget.selected);

  @override
  void didUpdateWidget(CategoryRibbon old) {
    super.didUpdateWidget(old);
    if (old.progress != widget.progress || old.withWork != widget.withWork || old.selected != widget.selected) {
      _from = RibbonGeometry.lerp(_from, _to, const Cubic(0.34, 1.2, 0.55, 1).transform(_morph.value));
      _to = _target;
      _morph.duration = PlannerMotion.ms(context, 620);
      _morph.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _morph.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = PlannerColors.of(context);
    final p = widget.progress;
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      return SizedBox(
        height: RibbonGeometry.height,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(
            child: Semantics(
              label: 'Stacked category ribbon of the week, Monday to Sunday',
              image: true,
              child: AnimatedBuilder(
                animation: _morph,
                builder: (context, _) => CustomPaint(
                  painter: _RibbonPainter(
                    RibbonGeometry.lerp(_from, _to, const Cubic(0.34, 1.2, 0.55, 1).transform(_morph.value)),
                    widget.reveal,
                    c.bg,
                    c.t3,
                  ),
                ),
              ),
            ),
          ),
          if (widget.onSelect != null) ...[
            AnimatedPositioned(
              duration: PlannerMotion.ms(context, 420),
              curve: PlannerMotion.settleCurve,
              left: widget.selected == null ? -10 : ribbonX(widget.selected!, w) - 0.5,
              top: -4,
              bottom: -4,
              width: 1,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: widget.selected == null ? 0 : 1,
                  duration: PlannerMotion.ms(context, 200),
                  child: ColoredBox(color: c.tx),
                ),
              ),
            ),
            for (var d = 0; d < 7; d++)
              Positioned(
                left: ribbonX(d, w) - 22,
                top: 0,
                bottom: 0,
                width: 44,
                child: Semantics(
                  button: true,
                  selected: widget.selected == d,
                  label: '${dayLongNames[d]}: ${dur(p.dayTotal(d, withWork: widget.withWork))} tracked',
                  onTap: () => widget.onSelect!(d),
                  child: GestureDetector(
                      behavior: HitTestBehavior.opaque, excludeFromSemantics: true, onTap: () => widget.onSelect!(d)),
                ),
              ),
          ],
        ]),
      );
    });
  }
}

class _RibbonPainter extends CustomPainter {
  _RibbonPainter(this.g, this.reveal, this.bg, this.t3);
  final RibbonGeometry g;
  final double reveal;
  final Color bg, t3;

  void _smooth(Path path, List<Offset> pts, {bool move = true}) {
    if (move) path.moveTo(pts[0].dx, pts[0].dy);
    for (var i = 1; i < pts.length; i++) {
      final a = pts[i - 1], b = pts[i], mx = (b.dx - a.dx) / 2;
      path.cubicTo(a.dx + mx, a.dy, b.dx - mx, b.dy, b.dx, b.dy);
    }
  }

  void _dashed(Canvas canvas, Path path, Paint p) {
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 5) {
        canvas.drawPath(m.extractPath(d, math.min(d + 2, m.length)), p);
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (reveal <= 0) return;
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(-2, -8, size.width * reveal, size.height + 8));
    final xs = [for (var d = 0; d < 7; d++) ribbonX(d, size.width)];
    final sep = Paint()
      ..color = bg
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final c in ribbonOrder) {
      final t = g.tops[c]!, b = g.bottoms[c]!;
      var thick = false;
      for (var i = 0; i < 7; i++) {
        if (b[i] - t[i] > 0.01) thick = true;
      }
      if (!thick) continue;
      final top = [for (var i = 0; i < 7; i++) Offset(xs[i], t[i])];
      final bot = [for (var i = 6; i >= 0; i--) Offset(xs[i], b[i])];
      final path = Path();
      _smooth(path, top);
      path.lineTo(bot[0].dx, bot[0].dy);
      _smooth(path, bot, move: false);
      path.close();
      canvas.drawPath(path, Paint()..color = c.color.withValues(alpha: g.opacity[c]!));
      canvas.drawPath(path, sep);
    }
    final env = Paint()
      ..color = t3
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final ys in [g.envTop, g.envBottom]) {
      final path = Path();
      _smooth(path, [for (var i = 0; i < 7; i++) Offset(xs[i], ys[i])]);
      _dashed(canvas, path, env);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RibbonPainter old) =>
      old.g != g || old.reveal != reveal || old.bg != bg || old.t3 != t3;
}
