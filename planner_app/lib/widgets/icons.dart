import 'package:flutter/material.dart';

/// The app's eight stroke icons (README 12), drawn from the prototype's
/// `ICON` paths on a 24 grid with a 1.5 stroke.
///
/// Deviation: README suggests Phosphor. `phosphor_flutter` 2.1.0 (its latest,
/// May 2024) does not compile on Flutter 3.44 because `IconData` became a
/// final class, so the same eight glyphs are painted here instead.
enum PIcon { plus, close, back, chev, sliders, mic, cloud, cloudOff }

class PlannerIcon extends StatelessWidget {
  const PlannerIcon(this.icon, {super.key, this.size = 22, this.color, this.stroke = 1.5, this.label});
  final PIcon icon;
  final double size;
  final Color? color;
  final double stroke;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? const Color(0xFF000000);
    return Semantics(
      label: label,
      excludeSemantics: label == null,
      child: CustomPaint(size: Size.square(size), painter: _IconPainter(icon, c, stroke)),
    );
  }
}

class _IconPainter extends CustomPainter {
  _IconPainter(this.icon, this.color, this.stroke);
  final PIcon icon;
  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 24;
    canvas.scale(k);
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    void line(double x0, double y0, double x1, double y1) =>
        canvas.drawLine(Offset(x0, y0), Offset(x1, y1), p);
    switch (icon) {
      case PIcon.plus:
        line(12, 5, 12, 19);
        line(5, 12, 19, 12);
      case PIcon.close:
        line(6, 6, 18, 18);
        line(18, 6, 6, 18);
      case PIcon.back:
        canvas.drawPath(Path()..moveTo(15, 5)..lineTo(8, 12)..lineTo(15, 19), p);
      case PIcon.chev:
        canvas.drawPath(Path()..moveTo(9, 5)..lineTo(16, 12)..lineTo(9, 19), p);
      case PIcon.sliders:
        line(4, 7, 13, 7);
        line(17, 7, 20, 7);
        line(4, 17, 7, 17);
        line(11, 17, 20, 17);
        canvas.drawCircle(const Offset(15, 7), 2, p);
        canvas.drawCircle(const Offset(9, 17), 2, p);
      case PIcon.mic:
        canvas.drawPath(
          Path()
            ..moveTo(12, 15)
            ..arcToPoint(const Offset(15, 12), radius: const Radius.circular(3), clockwise: false)
            ..lineTo(15, 6)
            ..arcToPoint(const Offset(9, 6), radius: const Radius.circular(3), clockwise: false)
            ..lineTo(9, 12)
            ..arcToPoint(const Offset(12, 15), radius: const Radius.circular(3), clockwise: false)
            ..close(),
          p,
        );
        canvas.drawPath(
          Path()
            ..moveTo(6, 11)
            ..arcToPoint(const Offset(18, 11), radius: const Radius.circular(6), clockwise: false),
          p,
        );
        line(12, 17, 12, 20);
      case PIcon.cloud:
      case PIcon.cloudOff:
        canvas.drawPath(
          Path()
            ..moveTo(7.5, 18)
            ..lineTo(17, 18)
            ..arcToPoint(const Offset(17.6, 11.05), radius: const Radius.circular(3.5), clockwise: false)
            ..arcToPoint(const Offset(7, 9.7), radius: const Radius.circular(5.5), clockwise: false)
            ..arcToPoint(const Offset(7.5, 18), radius: const Radius.circular(4.2), clockwise: false)
            ..close(),
          p,
        );
        if (icon == PIcon.cloudOff) line(4, 4, 20, 20);
    }
  }

  @override
  bool shouldRepaint(_IconPainter old) => old.icon != icon || old.color != color || old.stroke != stroke;
}
