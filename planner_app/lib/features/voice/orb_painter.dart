import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Live parameters of the orb (prototype `p`).
class OrbParams {
  double amp = 0, idle = 1, proc = 0, succ = 0, wob = 0, wobV = 0;
  double pulse = 0, cancel = 0, deny = 0;

  /// (start time, strength)
  final ripples = <(double, double)>[];
  Color core = const Color(0xFFECE9E2); // warm white [236, 233, 226]
}

const _tau = math.pi * 2;

/// Port of the prototype's `drawOrb` canvas renderer. All dimensions are
/// relative to the painted square's side [S], so it scales cleanly.
class OrbPainter extends CustomPainter {
  OrbPainter({required this.p, required this.t, required this.light, super.repaint});

  final OrbParams p;

  /// Seconds (frozen at 1.2 under reduced motion).
  final double t;
  final bool light;

  static Color _a(Color c, double a) => c.withValues(alpha: a.clamp(0.0, 1.0));
  static Color _mix(Color a, Color b, double q) => Color.lerp(a, b, q)!;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    var c = s / 2;
    final cy = s / 2;
    final core = p.core;
    final r = s * 0.2 * (1 + 0.06 * p.succ) * (1 - 0.08 * p.cancel);
    c += math.sin(t * 38) * p.cancel * r * 0.09;
    final center = Offset(c, cy);

    // Halo.
    final halo = math.min(1.0, p.amp) * (1 - p.succ) * (1 - p.deny);
    if (halo > 0.03) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = ui.Gradient.radial(center, r * 2.2,
              [_a(core, 0.18 * halo), _a(core, 0)], [0.9 / 2.2, 1]),
      );
    }

    // Ripples.
    for (final (t0, st) in p.ripples) {
      final age = (t - t0) / 1.7;
      if (age < 0 || age > 1) continue;
      canvas.drawCircle(
        center,
        r * (1.06 + age * 1.2),
        Paint()
          ..style = PaintingStyle.stroke
          ..color = _a(core, (1 - age) * (1 - age) * 0.6 * st)
          ..strokeWidth = s * (0.006 * (1 - age) + 0.0015),
      );
    }

    // Surface outline: 120 points, smoothed with quadratic midpoints.
    const m = 120;
    final pts = List<Offset>.generate(m, (i) {
      final th = i / m * _tau;
      var d = p.amp *
              (0.11 * math.sin(3 * th + t * 2.3) +
                  0.07 * math.sin(5 * th - t * 3.2) +
                  0.04 * math.sin(9 * th + t * 5.1)) +
          0.016 * math.sin(2 * th + t * 0.9) * (0.35 + p.idle) +
          p.wob * 0.08 * math.cos(2 * th) +
          p.proc * 0.03 * math.pow(math.max(0, math.cos(th - t * 2.6)), 6) -
          p.pulse * 0.05;
      d *= (1 - p.succ * 0.85);
      final rr = r * (1 + d);
      return Offset(c + rr * math.cos(th), cy + rr * math.sin(th));
    });
    Path surface() {
      final path = Path();
      for (var i = 0; i <= m; i++) {
        final a = pts[i % m], b = pts[(i + 1) % m];
        final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
        if (i == 0) {
          path.moveTo(mid.dx, mid.dy);
        } else {
          path.quadraticBezierTo(a.dx, a.dy, mid.dx, mid.dy);
        }
      }
      return path..close();
    }

    final body = surface();

    // Drop shadow, then the dark glass body.
    canvas.drawPath(
      body.shift(Offset(0, s * 0.025)),
      Paint()
        ..color = light ? const Color(0x4D19140A) : const Color(0xA6000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.03),
    );
    canvas.drawPath(
      body,
      Paint()
        ..shader = ui.Gradient.radial(
          center,
          r * 1.15,
          const [Color(0xFF3D3F44), Color(0xFF18191C), Color(0xFF050506)],
          const [0, 0.5, 1],
          TileMode.clamp,
          null,
          Offset(c - r * 0.35, cy - r * 0.42),
          r * 0.04,
        ),
    );

    canvas.save();
    canvas.clipPath(body);
    final lit = 1 - 0.7 * p.deny - 0.5 * p.cancel;

    // Spill of core light inside the glass.
    final spillC = Offset(c, cy + r * 0.2);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.radial(
            spillC, r * 1.15, [_a(core, 0.34 * lit), _a(core, 0)]),
    );

    // Core.
    final breath = 0.5 + 0.5 * math.sin(t * 1.5);
    var cr = r *
        (0.24 + 0.04 * breath * p.idle + p.amp * 0.2) *
        (1 - 0.5 * p.proc) *
        (1 - 0.3 * p.cancel);
    cr += (r * 0.95 - cr) * p.succ;
    Path corePath() {
      final path = Path();
      for (var i = 0; i <= 64; i++) {
        final th = i / 64 * _tau;
        final dd = 1 +
            p.amp *
                (0.16 * math.sin(2 * th - t * 3) + 0.09 * math.sin(4 * th + t * 4.2)) *
                (1 - p.succ);
        final x = c + cr * dd * math.cos(th), y = cy + cr * dd * math.sin(th);
        i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      return path..close();
    }

    final cp = corePath();
    if (p.deny > 0.5) {
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..color = _a(_mix(core, const Color(0xFF787A80), 0.5), 0.9)
        ..strokeWidth = s * 0.012;
      canvas.drawPath(cp, stroke);
      canvas.drawLine(Offset(c - cr * 0.8, cy + cr * 0.8),
          Offset(c + cr * 0.8, cy - cr * 0.8), stroke);
    } else {
      final alpha = 0.35 + 0.65 * lit;
      // Glow (shadowBlur R × .55 × lit).
      canvas.drawPath(
        cp,
        Paint()
          ..color = _a(core, 0.95 * lit * alpha)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, math.max(0.01, r * 0.55 * lit / 2)),
      );
      canvas.drawPath(
        cp,
        Paint()
          ..shader = ui.Gradient.radial(
            Offset(c, cy),
            cr * 1.15,
            [
              _a(_mix(core, Colors.white, 0.5), alpha),
              _a(core, alpha),
              _a(_mix(core, Colors.black, 0.22), alpha),
            ],
            const [0, 0.45, 1],
            TileMode.clamp,
            null,
            Offset(c - cr * 0.3, cy - cr * 0.35),
            0,
          ),
      );
    }

    // Processing droplets.
    if (p.proc > 0.02) {
      for (var k = 0; k < 3; k++) {
        final a = t * 2.8 + k * _tau / 3, rr = r * 0.46;
        canvas.drawCircle(
          Offset(c + math.cos(a) * rr, cy + math.sin(a) * rr),
          r * 0.085 * p.proc,
          Paint()..color = _a(_mix(core, Colors.white, 0.2), p.proc),
        );
      }
    }

    // Fresnel rim.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.radial(center, r * 1.1,
            const [Color(0x00FFFFFF), Color(0x24FFFFFF)], const [0.72 / 1.1, 1]),
    );

    // Specular highlight.
    canvas.save();
    canvas.translate(c - r * 0.34 + p.wob * r * 0.05, cy - r * 0.5);
    canvas.rotate(-0.5);
    canvas.scale(1, 0.55);
    canvas.drawCircle(
      Offset.zero,
      r * 0.44,
      Paint()
        ..shader = ui.Gradient.radial(Offset.zero, r * 0.44,
            const [Color(0x8CFFFFFF), Color(0x1FFFFFFF), Color(0x00FFFFFF)], const [0, 0.45, 1]),
    );
    canvas.restore();
    canvas.restore();

    // Edge highlight.
    canvas.drawPath(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.003
        ..shader = ui.Gradient.linear(
          Offset(c - r, cy - r),
          Offset(c + r, cy + r),
          const [Color(0x66FFFFFF), Color(0x0DFFFFFF), Color(0x29FFFFFF)],
          const [0, 0.5, 1],
        ),
    );

    // Success tick.
    if (p.succ > 0.35) {
      final q = math.min(1.0, (p.succ - 0.35) / 0.55);
      final pp = [
        Offset(c - 0.26 * r, cy + 0.01 * r),
        Offset(c - 0.07 * r, cy + 0.19 * r),
        Offset(c + 0.27 * r, cy - 0.17 * r),
      ];
      final l1 = (pp[1] - pp[0]).distance, l2 = (pp[2] - pp[1]).distance;
      var len = q * (l1 + l2);
      final tick = Path()..moveTo(pp[0].dx, pp[0].dy);
      if (len <= l1) {
        final e = Offset.lerp(pp[0], pp[1], len / l1)!;
        tick.lineTo(e.dx, e.dy);
      } else {
        tick.lineTo(pp[1].dx, pp[1].dy);
        len -= l1;
        final e = Offset.lerp(pp[1], pp[2], len / l2)!;
        tick.lineTo(e.dx, e.dy);
      }
      final lum = core.computeLuminance();
      // The prototype used perceived luma > .62; relative luminance ~.35.
      canvas.drawPath(
        tick,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = s * 0.022
          ..color = _perceived(core) > 0.62 || lum > 0.6
              ? const Color(0xFF1A1404)
              : Colors.white,
      );
    }
  }

  static double _perceived(Color c) =>
      0.299 * c.r + 0.587 * c.g + 0.114 * c.b;

  @override
  bool shouldRepaint(OrbPainter old) => true;
}
