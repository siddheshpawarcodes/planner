import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../app/theme/planner_theme.dart';
import 'orb_painter.dart';

/// Orb states (README 6.3).
enum OrbState { idle, wake, listening, processing, result, success, cancelled, denied }

/// Imperative handle for one-shot impulses (tap wobble, success ripple,
/// cancel shake) that don't map onto a steady state.
class OrbController {
  _PlannerOrbState? _s;
  void tapImpulse() => _s?._impulse();
  void successRipple() => _s?._ripple(1);
  void cancelShake() => _s?._cancel();
}

/// `PlannerOrb`: CustomPainter + Ticker, renderer ported from `drawOrb`.
/// Ambient breathing pauses when [ambient] is false (voice, drag, sheets).
class PlannerOrb extends StatefulWidget {
  const PlannerOrb({
    super.key,
    required this.state,
    this.core,
    this.level,
    this.speaking = false,
    this.hover = false,
    this.controller,
    this.size = 240,
  });

  final OrbState state;

  /// Core colour: the current task's (or scheduled task's) category, or null
  /// for warm white.
  final Color? core;

  /// Live mic level 0..1 (RMS × 7, clamped), or null when not listening.
  final double? level;

  /// Demo speech (no live mic): drives a synthetic amplitude.
  final bool speaking;
  final bool hover;
  final OrbController? controller;
  final double size;

  @override
  State<PlannerOrb> createState() => _PlannerOrbState();
}

class _PlannerOrbState extends State<PlannerOrb> with SingleTickerProviderStateMixin {
  final p = OrbParams();
  late final Ticker _ticker = createTicker(_frame);
  final _repaint = ValueNotifier<int>(0);
  Duration _last = Duration.zero;
  double _t = 0;
  double _lastRipple = -10;
  bool _reduced = false;

  @override
  void initState() {
    super.initState();
    widget.controller?._s = this;
    _ticker.start();
  }

  @override
  void didUpdateWidget(PlannerOrb old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?._s = null;
      widget.controller?._s = this;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = PlannerMotion.reduced(context);
  }

  @override
  void dispose() {
    widget.controller?._s = null;
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  void _impulse() {
    p.wobV += 9;
    p.pulse = 1;
  }

  void _ripple(double s) => p.ripples.add((_reduced ? 1.2 : _t, s));

  void _cancel() => p.cancel = 1;

  void _frame(Duration elapsed) {
    final dt = math.min(0.05, (elapsed - _last).inMicroseconds / 1e6);
    _last = elapsed;
    _t = elapsed.inMicroseconds / 1e6;
    final rm = _reduced, t = rm ? 1.2 : _t;
    var amp = widget.hover ? 0.16 : 0.03, idle = 1.0, proc = 0.0, succ = 0.0, deny = 0.0;
    switch (widget.state) {
      case OrbState.wake:
        amp = 0.45;
        idle = 0;
      case OrbState.listening:
        idle = 0;
        final lv = widget.level;
        amp = lv != null
            ? 0.12 + lv * 0.95
            : widget.speaking
                ? 0.35 + 0.65 * (math.sin(t * 9.3) * math.sin(t * 2.7 + 1)).abs()
                : 0.14;
      case OrbState.processing:
        idle = 0;
        amp = 0.05;
        proc = 1;
      case OrbState.result:
        idle = 0.6;
        amp = 0.06;
      case OrbState.success:
        idle = 0;
        amp = 0;
        succ = 1;
      case OrbState.denied:
        idle = 0.4;
        amp = 0.02;
        deny = 1;
      case OrbState.idle:
      case OrbState.cancelled:
        break;
    }
    final k = rm ? 1.0 : 1 - math.exp(-dt * 10);
    p.amp += (amp - p.amp) * k;
    p.idle += (idle - p.idle) * k;
    p.proc += (proc - p.proc) * k;
    p.deny += (deny - p.deny) * k;
    p.succ += (succ - p.succ) * (rm ? 1 : 1 - math.exp(-dt * (succ > 0 ? 5 : 12)));
    if (!rm) {
      final a = -260 * p.wob - 14 * p.wobV;
      p.wobV += a * dt;
      p.wob += p.wobV * dt;
      p.pulse *= math.exp(-dt * 7);
      p.cancel *= math.exp(-dt * 3.2);
    } else {
      p.wob = 0;
      p.pulse = 0;
      p.cancel = 0;
    }
    if (widget.state == OrbState.listening && !rm && p.amp > 0.62 && t - _lastRipple > 0.42) {
      _lastRipple = t;
      p.ripples.add((t, p.amp));
    }
    p.ripples.removeWhere((r) => t - r.$1 >= 1.8);
    p.core = widget.core ?? const Color(0xFFECE9E2);
    _repaint.value++;
  }

  @override
  Widget build(BuildContext context) {
    final light = !PlannerColors.of(context).isDark;
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.square(widget.size),
        painter: _OrbHost(this, light),
      ),
    );
  }
}

class _OrbHost extends CustomPainter {
  _OrbHost(this.s, this.light) : super(repaint: s._repaint);
  final _PlannerOrbState s;
  final bool light;
  @override
  void paint(Canvas canvas, Size size) =>
      OrbPainter(p: s.p, t: s._reduced ? 1.2 : s._t, light: light).paint(canvas, size);
  @override
  bool shouldRepaint(_OrbHost old) => old.light != light;
}
