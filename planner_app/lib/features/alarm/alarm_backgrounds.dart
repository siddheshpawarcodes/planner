import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:video_player/video_player.dart';

import '../../app/theme/category_style.dart';
import '../../data/alarm_prefs.dart';
import '../voice/orb_painter.dart';

/// The alarm screen's background: a built-in look, a photo or GIF, a
/// looping video or the category colour, then the effects (slow zoom, blur,
/// tint, dim). Everything is drawn in code; reduced motion holds a still
/// frame. A missing photo or video falls back to the category look.
class AlarmBackground extends StatefulWidget {
  const AlarmBackground({super.key, required this.look, required this.cat, this.reduced = false});

  final AlarmLook look;
  final Category cat;
  final bool reduced;

  @override
  State<AlarmBackground> createState() => _AlarmBackgroundState();
}

class _AlarmBackgroundState extends State<AlarmBackground> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((d) => _t.value = d.inMicroseconds / 1e6);
  final _t = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(AlarmBackground old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.reduced) {
      if (_ticker.isActive) _ticker.stop();
      _t.value = 6; // a settled, representative frame
    } else if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _t.dispose();
    super.dispose();
  }

  bool get _mediaOk {
    final p = widget.look.mediaPath;
    return p != null && File(p).existsSync();
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.look;
    final accent = widget.cat.color;
    Widget base = switch (l.bg) {
      AlarmBg.look => _LookLayer(id: l.lookId, accent: accent, t: _t),
      AlarmBg.photo when _mediaOk => Image.file(
          File(l.mediaPath!),
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => _CategoryLayer(accent: accent, t: _t),
        ),
      AlarmBg.video when _mediaOk => _VideoLayer(path: l.mediaPath!, play: !widget.reduced),
      _ => _CategoryLayer(accent: accent, t: _t),
    };
    if (l.zoom && !widget.reduced) base = _SlowZoom(t: _t, child: base);
    if (l.blur > 0.01) {
      final s = l.blur * 28;
      base = ImageFiltered(imageFilter: ui.ImageFilter.blur(sigmaX: s, sigmaY: s, tileMode: TileMode.mirror), child: base);
    }
    final tint = l.tintCategory ? accent : (l.tint != null ? Color(l.tint!) : null);
    if (tint != null && l.tintStrength > 0.01) {
      base = ColorFiltered(
        colorFilter: ColorFilter.mode(tint.withValues(alpha: l.tintStrength * 0.85), BlendMode.color),
        child: base,
      );
    }
    return ClipRect(
      child: Stack(fit: StackFit.expand, children: [
        const ColoredBox(color: Color(0xFF05060A)),
        base,
        // Dim, and a floor so the actions always read.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: l.dim * 0.8),
                Colors.black.withValues(alpha: l.dim * 0.7),
                Colors.black.withValues(alpha: math.min(0.9, l.dim * 0.8 + 0.35)),
              ],
              stops: const [0, 0.55, 1],
            ),
          ),
        ),
      ]),
    );
  }
}

/// Ken Burns: 1.0 → 1.12 and back over 40 s, drifting slightly.
class _SlowZoom extends StatelessWidget {
  const _SlowZoom({required this.t, required this.child});
  final ValueNotifier<double> t;
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double>(
        valueListenable: t,
        child: child,
        builder: (context, v, child) {
          final q = 0.5 - 0.5 * math.cos(v * math.pi * 2 / 40);
          return Transform.scale(
            scale: 1 + 0.12 * q,
            alignment: Alignment(0.3 * math.sin(v / 13), 0.2 * math.cos(v / 17)),
            child: child,
          );
        },
      );
}

class _VideoLayer extends StatefulWidget {
  const _VideoLayer({required this.path, required this.play});
  final String path;
  final bool play;

  @override
  State<_VideoLayer> createState() => _VideoLayerState();
}

class _VideoLayerState extends State<_VideoLayer> {
  VideoPlayerController? _c;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void didUpdateWidget(_VideoLayer old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) {
      _c?.dispose();
      _c = null;
      _open();
    } else if (old.play != widget.play) {
      widget.play ? _c?.play() : _c?.pause();
    }
  }

  Future<void> _open() async {
    final c = VideoPlayerController.file(File(widget.path),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
    _c = c;
    try {
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(0); // the alarm tone is the sound
      if (widget.play) await c.play();
    } catch (_) {}
    if (mounted && _c == c) setState(() {});
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null || !c.value.isInitialized) return const SizedBox.expand();
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(width: c.value.size.width, height: c.value.size.height, child: VideoPlayer(c)),
    );
  }
}

/// The category colour: a deep gradient with a slowly breathing glow.
class _CategoryLayer extends StatelessWidget {
  const _CategoryLayer({required this.accent, required this.t});
  final Color accent;
  final ValueNotifier<double> t;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _CategoryPainter(accent, t), size: Size.infinite);
}

class _CategoryPainter extends CustomPainter {
  _CategoryPainter(this.accent, this.t) : super(repaint: t);
  final Color accent;
  final ValueNotifier<double> t;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    final deep = Color.lerp(accent, Colors.black, 0.78)!;
    canvas.drawRect(
      r,
      Paint()
        ..shader = ui.Gradient.linear(r.topCenter, r.bottomCenter,
            [Color.lerp(accent, Colors.black, 0.35)!, deep, Colors.black], const [0, 0.55, 1]),
    );
    final b = 0.5 + 0.5 * math.sin(t.value * 0.9);
    final c = Offset(size.width * 0.5, size.height * 0.36);
    canvas.drawRect(
      r,
      Paint()
        ..shader = ui.Gradient.radial(c, size.longestSide * (0.45 + 0.08 * b),
            [accent.withValues(alpha: 0.55 + 0.2 * b), accent.withValues(alpha: 0)]),
    );
  }

  @override
  bool shouldRepaint(_CategoryPainter o) => o.accent != accent;
}

class _LookLayer extends StatelessWidget {
  const _LookLayer({required this.id, required this.accent, required this.t});
  final AlarmLookId id;
  final Color accent;
  final ValueNotifier<double> t;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.infinite,
        painter: switch (id) {
          AlarmLookId.orb => _OrbLook(accent, t),
          AlarmLookId.aurora => _AuroraLook(accent, t),
          AlarmLookId.embers => _EmbersLook(accent, t),
          AlarmLookId.stars => _StarsLook(accent, t),
          AlarmLookId.sunrise => _SunriseLook(accent, t),
          AlarmLookId.waves => _WavesLook(accent, t),
        },
      );
}

List<double> _stops(int n) => [for (var i = 0; i < n; i++) i / (n - 1)];

abstract class _Look extends CustomPainter {
  _Look(this.accent, this.t) : super(repaint: t);
  final Color accent;
  final ValueNotifier<double> t;

  @override
  bool shouldRepaint(_Look o) => o.runtimeType != runtimeType || o.accent != accent;

  static Color hue(Color c, double deg, {double? s, double? l}) {
    final h = HSLColor.fromColor(c);
    return h
        .withHue((h.hue + deg) % 360)
        .withSaturation(s ?? h.saturation)
        .withLightness(l ?? h.lightness)
        .toColor();
  }

  /// Deterministic pseudo-random in 0..1 for particle [i], channel [k].
  static double rnd(int i, int k) {
    final x = math.sin(i * 12.9898 + k * 78.233) * 43758.5453;
    return x - x.floorToDouble();
  }

  void fill(Canvas canvas, Size size, List<Color> colors) {
    final r = Offset.zero & size;
    canvas.drawRect(r, Paint()..shader = ui.Gradient.linear(r.topCenter, r.bottomCenter, colors, _stops(colors.length)));
  }
}

/// Planner's orb, large and breathing, in the task's colour.
class _OrbLook extends _Look {
  _OrbLook(super.accent, super.t);
  final _p = OrbParams();

  @override
  void paint(Canvas canvas, Size size) {
    final v = t.value;
    fill(canvas, size, [
      Color.lerp(accent, Colors.black, 0.82)!,
      const Color(0xFF07080C),
      Colors.black,
    ]);
    final s = size.width * 1.25;
    _p
      ..core = Color.lerp(accent, Colors.white, 0.25)!
      ..idle = 1
      // Low amplitude: at this size a voice-level wobble reads as lumps.
      ..amp = 0.16 + 0.1 * (0.5 + 0.5 * math.sin(v * 1.4));
    canvas.save();
    canvas.translate((size.width - s) / 2, size.height * 0.34 - s / 2);
    OrbPainter(p: _p, t: v, light: false).paint(canvas, Size.square(s));
    canvas.restore();
  }
}

/// Soft colour fields drifting like an aurora.
class _AuroraLook extends _Look {
  _AuroraLook(super.accent, super.t);

  @override
  void paint(Canvas canvas, Size size) {
    final v = t.value;
    fill(canvas, size, const [Color(0xFF04060D), Color(0xFF070A14), Color(0xFF020306)]);
    final cols = [
      accent,
      _Look.hue(accent, 50, s: 0.8, l: 0.55),
      _Look.hue(accent, 160, s: 0.7, l: 0.5),
      const Color(0xFF2EE6C3),
    ];
    final w = size.width, h = size.height;
    for (var i = 0; i < cols.length; i++) {
      final a = v * (0.11 + i * 0.03) + i * 1.7;
      final c = Offset(w * (0.5 + 0.38 * math.sin(a)), h * (0.32 + 0.22 * math.cos(a * 1.3 + i)));
      final r = w * (0.75 + 0.15 * math.sin(a * 0.7));
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = ui.Gradient.radial(c, r, [cols[i].withValues(alpha: 0.42), cols[i].withValues(alpha: 0)]),
      );
    }
  }
}

/// Embers rising and swaying, glowing warm with the task's colour.
class _EmbersLook extends _Look {
  _EmbersLook(super.accent, super.t);

  @override
  void paint(Canvas canvas, Size size) {
    final v = t.value;
    fill(canvas, size, [const Color(0xFF0C0705), const Color(0xFF070405), Color.lerp(accent, Colors.black, 0.7)!]);
    final warm = const Color(0xFFFF8A3D);
    for (var i = 0; i < 90; i++) {
      final speed = 0.03 + 0.06 * _Look.rnd(i, 1);
      final y = 1 - ((_Look.rnd(i, 2) + v * speed) % 1.0);
      final x = _Look.rnd(i, 3) + 0.03 * math.sin(v * (0.6 + _Look.rnd(i, 4)) + i);
      final r = 1 + 3 * _Look.rnd(i, 5);
      final life = math.sin(math.pi * (1 - y)).clamp(0.0, 1.0);
      final col = Color.lerp(warm, accent, _Look.rnd(i, 6) * 0.6)!;
      final p = Offset(x * size.width, y * size.height);
      canvas.drawCircle(
          p,
          r * 4,
          Paint()
            ..shader = ui.Gradient.radial(p, r * 4, [col.withValues(alpha: 0.35 * life), col.withValues(alpha: 0)]));
      canvas.drawCircle(p, r * 0.7, Paint()..color = Colors.white.withValues(alpha: 0.75 * life));
    }
  }
}

/// A starfield: twinkling stars, a faint nebula and the odd shooting star.
class _StarsLook extends _Look {
  _StarsLook(super.accent, super.t);

  @override
  void paint(Canvas canvas, Size size) {
    final v = t.value;
    final w = size.width, h = size.height;
    fill(canvas, size, const [Color(0xFF02030A), Color(0xFF050814), Color(0xFF02030A)]);
    final neb = Offset(w * 0.7, h * 0.25);
    canvas.drawCircle(neb, w,
        Paint()..shader = ui.Gradient.radial(neb, w, [accent.withValues(alpha: 0.22), accent.withValues(alpha: 0)]));
    for (var i = 0; i < 170; i++) {
      final depth = 0.3 + 0.7 * _Look.rnd(i, 1);
      final x = (_Look.rnd(i, 2) + v * 0.004 * depth) % 1.0;
      final y = _Look.rnd(i, 3);
      final tw = 0.5 + 0.5 * math.sin(v * (1 + 3 * _Look.rnd(i, 4)) + i);
      canvas.drawCircle(Offset(x * w, y * h), 0.5 + 1.3 * depth,
          Paint()..color = Colors.white.withValues(alpha: (0.25 + 0.75 * tw) * depth));
    }
    // A shooting star every 7 s, for 0.9 s.
    final k = (v / 7).floor();
    final ph = (v % 7) / 0.9;
    if (ph < 1) {
      final sx = w * (0.2 + 0.6 * _Look.rnd(k, 7)), sy = h * (0.08 + 0.3 * _Look.rnd(k, 8));
      final a = Offset(sx + ph * w * 0.35, sy + ph * h * 0.12);
      final b = a - Offset(w * 0.12, h * 0.04);
      canvas.drawLine(
          b,
          a,
          Paint()
            ..strokeWidth = 1.6
            ..strokeCap = StrokeCap.round
            ..shader = ui.Gradient.linear(b, a, [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: 0.9 * (1 - ph))]));
    }
  }
}

/// Night turning to dawn over the first minute, the sun rising with it.
/// It pairs with a gentle start.
class _SunriseLook extends _Look {
  _SunriseLook(super.accent, super.t);

  @override
  void paint(Canvas canvas, Size size) {
    final q = Curves.easeInOut.transform((t.value / 50).clamp(0.0, 1.0));
    final w = size.width, h = size.height;
    Color mix(int a, int b) => Color.lerp(Color(a), Color(b), q)!;
    final r = Offset.zero & size;
    canvas.drawRect(
      r,
      Paint()
        ..shader = ui.Gradient.linear(r.topCenter, r.bottomCenter, [
          mix(0xFF03040E, 0xFF1F3B7A),
          mix(0xFF0B0F2A, 0xFF8E6BB0),
          mix(0xFF1A1030, 0xFFFF9A5A),
          mix(0xFF120A14, 0xFFFFC27A),
        ], const [0, 0.45, 0.75, 1]),
    );
    final sun = Offset(w * 0.5, h * (0.95 - 0.33 * q));
    final glow = w * (0.9 + 0.3 * q);
    canvas.drawCircle(sun, glow,
        Paint()..shader = ui.Gradient.radial(sun, glow, [const Color(0xFFFFB061).withValues(alpha: 0.55 * (0.3 + q)), const Color(0x00FFB061)]));
    canvas.drawCircle(sun, w * 0.13, Paint()..color = Color.lerp(const Color(0xFFFF7A3D), const Color(0xFFFFE2A8), q)!);
    // Hills in front of the sun, tinted toward the task's colour.
    final hill = Path()..moveTo(0, h);
    for (var x = 0.0; x <= w; x += 8) {
      hill.lineTo(x, h * 0.86 + math.sin(x / w * math.pi * 2.2 + 0.8) * h * 0.035);
    }
    hill
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(hill, Paint()..color = Color.lerp(const Color(0xFF07060C), Color.lerp(accent, Colors.black, 0.7)!, 0.5)!);
  }
}

/// Layered waves rolling slowly at the bottom of the screen.
class _WavesLook extends _Look {
  _WavesLook(super.accent, super.t);

  @override
  void paint(Canvas canvas, Size size) {
    final v = t.value;
    final w = size.width, h = size.height;
    fill(canvas, size, [const Color(0xFF03060C), Color.lerp(accent, Colors.black, 0.86)!, Color.lerp(accent, Colors.black, 0.6)!]);
    for (var i = 0; i < 5; i++) {
      final base = h * (0.55 + i * 0.09);
      final amp = h * (0.03 - i * 0.003);
      final path = Path()..moveTo(0, h);
      for (var x = 0.0; x <= w + 8; x += 8) {
        path.lineTo(
            x,
            base +
                math.sin(x / w * math.pi * (2 + i * 0.5) + v * (0.5 + i * 0.15) + i) * amp +
                math.sin(x / w * math.pi * 5 - v * 0.7) * amp * 0.3);
      }
      path
        ..lineTo(w, h)
        ..close();
      canvas.drawPath(
          path,
          Paint()
            ..color = Color.lerp(_Look.hue(accent, i * 12.0), Colors.black, 0.25 + i * 0.12)!.withValues(alpha: 0.35 + i * 0.12));
    }
  }
}
