import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Surface language (README 3.4): 135° hatch = protected, category stripes =
/// overflow, dashed hairline = open, dashed outline task = missed.

/// Repeating 135° lines, like CSS
/// `repeating-linear-gradient(135deg, color 0 w, transparent w period)`.
class HatchPainter extends CustomPainter {
  const HatchPainter({required this.color, this.width = 1, this.period = 7});
  final Color color;
  final double width, period;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final p = Paint()
      ..color = color
      ..strokeWidth = width
      ..isAntiAlias = true;
    // 135° gradient stripes run along the 45° diagonal (bottom-left → top-right).
    final step = period * math.sqrt2;
    for (var x = -size.height; x < size.width + size.height; x += step) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), p);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(HatchPainter old) =>
      old.color != color || old.width != width || old.period != period;
}

class Hatch extends StatelessWidget {
  const Hatch({super.key, required this.color, this.width = 1, this.period = 7, this.radius = 4});
  final Color color;
  final double width, period, radius;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: CustomPaint(
          painter: HatchPainter(color: color, width: width, period: period),
          child: const SizedBox.expand(),
        ),
      );
}

/// A dashed rounded-rectangle outline (open time, missed tasks).
class DashedBorderPainter extends CustomPainter {
  const DashedBorderPainter({
    required this.color,
    this.radius = 4,
    this.strokeWidth = 1,
    this.dash = 4,
    this.gap = 3,
  });
  final Color color;
  final double radius, strokeWidth, dash, gap;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
        (Offset.zero & size).deflate(strokeWidth / 2), Radius.circular(radius));
    final path = Path()..addRRect(r);
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + dash, m.length)), p);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(DashedBorderPainter old) =>
      old.color != color || old.radius != radius || old.strokeWidth != strokeWidth;
}

class DashedBox extends StatelessWidget {
  const DashedBox({
    super.key,
    required this.color,
    this.radius = 4,
    this.strokeWidth = 1,
    this.dash = 4,
    this.gap = 3,
    this.child,
  });
  final Color color;
  final double radius, strokeWidth, dash, gap;
  final Widget? child;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: DashedBorderPainter(
            color: color, radius: radius, strokeWidth: strokeWidth, dash: dash, gap: gap),
        child: child ?? const SizedBox.expand(),
      );
}

/// A horizontal dashed hairline (breaks).
class DashedLine extends StatelessWidget {
  const DashedLine({super.key, required this.color, this.dash = 4, this.gap = 3});
  final Color color;
  final double dash, gap;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: const Size(double.infinity, 1),
        painter: _DashedLinePainter(color, dash, gap),
      );
}

class _DashedLinePainter extends CustomPainter {
  _DashedLinePainter(this.color, this.dash, this.gap);
  final Color color;
  final double dash, gap;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += dash + gap) {
      canvas.drawLine(Offset(x, 0.5), Offset(math.min(x + dash, size.width), 0.5), p);
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter old) => old.color != color;
}

/// Vertical dotted fill (the capacity buffer zone).
class DotsPainter extends CustomPainter {
  const DotsPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    for (var x = 0.0; x < size.width; x += 3) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 1, size.height), p);
    }
  }

  @override
  bool shouldRepaint(DotsPainter old) => old.color != color;
}
