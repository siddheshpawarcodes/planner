import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/state/actions.dart';
import '../../app/state/clock.dart';
import '../../app/state/ui_state.dart';
import '../../app/theme/planner_theme.dart';
import '../../domain/base_day.dart';
import '../../domain/task.dart';
import '../../domain/time.dart';
import '../../widgets/controls.dart';
import 'today_model.dart';

const _size = 320.0, _r0 = 128.0;

class _Arc {
  _Arc(this.m0, this.m1, this.color, this.width,
      {this.dash, this.opacity = 1, this.order = 0, this.taskId, this.drawIn = true});
  final double m0, m1;
  final Color color;
  final double width;
  final List<double>? dash;
  final double opacity;
  final int order;
  final String? taskId;
  final bool drawIn;
}

/// The Dial (README 6.2): 24h around a 320px face.
class DialView extends ConsumerStatefulWidget {
  const DialView({super.key});
  @override
  ConsumerState<DialView> createState() => _DialViewState();
}

class _DialViewState extends ConsumerState<DialView> with SingleTickerProviderStateMixin {
  late final _draw = AnimationController(vsync: this, value: 1);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _replay());
  }

  void _replay() {
    if (!mounted) return;
    _draw.duration = PlannerMotion.ms(context, 700 + 45 * 16);
    _draw.forward(from: 0);
    ref.read(todayUiProvider.notifier).set((s) => s.copyWith(dialIn: true));
  }

  @override
  void dispose() {
    _draw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = PlannerColors.of(context);
    final m = ref.watch(todayModelProvider);
    final ui = ref.watch(todayUiProvider);
    final act = ref.read(actionsProvider);
    ref.listen(todayUiProvider.select((u) => u.dialIn), (a, b) {
      if (b == false) _replay();
    });
    final r = m.routine;

    final arcs = <_Arc>[
      _Arc(math.max(0, r.sleep - 1440).toDouble(), r.wake.toDouble(), c.t3, 2,
          dash: const [2, 6], opacity: 0.8, drawIn: false),
      if (r.sleep < 1440)
        _Arc(r.sleep.toDouble(), 1440, c.t3, 2, dash: const [2, 6], opacity: 0.8, drawIn: false),
    ];
    for (final (i, it) in m.layout.seq.indexed) {
      if (it.kind == ItemKind.marker || it.kind == ItemKind.breakTime) continue;
      final a = it.start + 3.0, b = it.end - 3.0;
      if (b <= a) continue;
      switch (it.kind) {
        case ItemKind.fixed:
          arcs.add(_Arc(a, b, (it.cat ?? Category.work).tintAt(c, 0.55), 8, order: i));
        case ItemKind.protected:
          arcs.add(_Arc(a, b, c.t3, 2, dash: const [1, 3], opacity: 0.7, order: i, drawIn: false));
        case ItemKind.open:
          arcs.add(_Arc(a, b, c.ln, 2, order: i));
        case ItemKind.task:
          final t = m.layout.tasks.firstWhere((x) => x.id == it.taskId);
          if (m.staging.place[t.id] != null && m.staging.isHiddenOrStaged(t.id)) continue;
          final missed = m.isMissedTask(t);
          final hot = m.cur?.id == t.id || m.next?.id == t.id;
          arcs.add(_Arc(
            a,
            b,
            t.done
                ? c.ln
                : missed
                    ? c.t3
                    : hot
                        ? t.cat.color
                        : t.cat.tintAt(c, 0.6),
            ui.dialSel == t.id ? 26 : 20,
            dash: missed ? const [3, 4] : null,
            order: i,
            taskId: t.id,
            drawIn: !missed,
          ));
        default:
          break;
      }
    }

    Task? byId(String? id) {
      for (final t in m.dayTasks) {
        if (t.id == id) return t;
      }
      return null;
    }

    final focus = byId(ui.dialSel) ?? m.cur ?? m.next ?? (m.isToday ? null : m.dayTasks.firstOrNull);
    String label, title, meta;
    Color labelC;
    var canDone = false, canDecide = false;
    if (focus != null) {
      final miss = m.isMissedTask(focus);
      label = focus.done
          ? 'DONE'
          : m.cur?.id == focus.id
              ? 'NOW'
              : miss
                  ? 'MISSED'
                  : m.isToday
                      ? 'NEXT'
                      : 'FIRST';
      title = focus.title;
      meta = '${fmt(focus.start!)} → ${fmt(focus.end!)}';
      canDone = m.isToday && !focus.done && !miss;
      canDecide = miss;
      labelC = focus.cat.color;
    } else {
      label = m.isToday ? 'TODAY' : 'TOMORROW';
      title = m.dayTasks.isNotEmpty ? 'All done' : 'No plans yet';
      meta = m.dayTasks.isNotEmpty ? '${m.doneCount} of ${m.dayTasks.length}' : 'Tap the orb';
      labelC = c.tx;
    }

    final upNext = [
      for (final t in m.dayTasks)
        if (!m.isToday || t.end! > m.now) t
    ].take(4).toList();

    void tapAt(Offset p) {
      final d = p - const Offset(_size / 2, _size / 2);
      final rad = d.distance;
      if (rad < _r0 - 16 || rad > _r0 + 16) return;
      var ang = math.atan2(d.dy, d.dx) + math.pi / 2;
      if (ang < 0) ang += math.pi * 2;
      final minute = ang / (math.pi * 2) * 1440;
      for (final a in arcs) {
        if (a.taskId != null && minute >= a.m0 - 6 && minute <= a.m1 + 6) {
          ref.read(todayUiProvider.notifier).set((s) => s.copyWith(dialSel: a.taskId));
          return;
        }
      }
    }

    final now = ref.watch(nowProvider);
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 14, bottom: 30),
      child: Column(children: [
        SizedBox(
          width: _size,
          height: _size,
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned.fill(
              child: GestureDetector(
                onTapUp: (d) => tapAt(d.localPosition),
                child: AnimatedBuilder(
                  animation: _draw,
                  builder: (context, _) => CustomPaint(
                    painter: _DialPainter(arcs: arcs, c: c, progress: _draw.value * (700 + 45 * 16)),
                  ),
                ),
              ),
            ),
            if (m.isToday)
              Positioned.fill(
                child: IgnorePointer(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: now / 1440),
                    duration: const Duration(seconds: 1),
                    builder: (context, v, _) =>
                        CustomPaint(painter: _HandPainter(v, c.tx)),
                  ),
                ),
              ),
            for (final (l, a) in [
              ('00', const Alignment(0, -1.03)),
              ('06', const Alignment(1.03, 0)),
              ('12', const Alignment(0, 1.03)),
              ('18', const Alignment(-1.03, 0)),
            ])
              Align(alignment: a, child: Text(l, style: PlannerType.time(size: 10, weight: 500, color: c.t3))),
            Positioned(
              left: 60,
              right: 60,
              top: 60,
              bottom: 60,
              child: Semantics(
                liveRegion: true,
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(label, style: PlannerType.stateLabel(size: 10, tracking: 0.1, color: labelC)),
                  const SizedBox(height: 4),
                  Text(title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: PlannerType.bricolage600(21, height: 1.12, tracking: -0.01, color: c.tx)),
                  const SizedBox(height: 4),
                  Text(meta, style: PlannerType.time(size: 12, color: c.t3)),
                  if (canDone) ...[
                    const SizedBox(height: 8),
                    PrimaryPill(label: 'Mark done', height: 40, onTap: () => act.toggle(focus!.id)),
                  ],
                  if (canDecide) ...[
                    const SizedBox(height: 8),
                    SecondaryPill(label: 'Decide', height: 40, onTap: () => act.openDecision(focus!.id)),
                  ],
                ]),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: 360,
          child: Column(children: [
            for (final t in upNext)
              Pressable(
                onTap: () => act.openBlock(t.id),
                label: '${t.title}, ${fmt(t.start!)} to ${fmt(t.end!)}',
                radius: 0,
                pressedScale: 0.99,
                excludeChildSemantics: true,
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(border: Border(top: BorderSide(color: c.ln))),
                  child: Row(children: [
                    CatSquare(t.cat.color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(t.title,
                          style: PlannerType.ui(14, weight: 400, color: t.done ? c.t3 : c.tx).copyWith(
                              decoration: t.done ? TextDecoration.lineThrough : null)),
                    ),
                    Text('${fmt(t.start!)} → ${fmt(t.end!)}', style: PlannerType.time(size: 12, color: c.t3)),
                  ]),
                ),
              ),
            if (upNext.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: c.ln))),
                child: Text('Nothing else today. The evening is yours.',
                    textAlign: TextAlign.center, style: PlannerType.ui(13, weight: 400, color: c.t2)),
              ),
          ]),
        ),
      ]),
    );
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter({required this.arcs, required this.c, required this.progress});
  final List<_Arc> arcs;
  final PlannerColors c;

  /// Milliseconds into the draw-in (700 per arc, 45ms stagger).
  final double progress;

  static const _center = Offset(_size / 2, _size / 2);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(
        _center,
        _r0,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 22
          ..color = c.s1);
    final tick = Paint()
      ..color = c.t3
      ..strokeWidth = 1;
    for (var i = 0; i < 24; i++) {
      final a = i / 24 * math.pi * 2 - math.pi / 2;
      final r2 = i % 6 == 0 ? 154.0 : 150.0;
      canvas.drawLine(_center + Offset(math.cos(a), math.sin(a)) * 146,
          _center + Offset(math.cos(a), math.sin(a)) * r2, tick);
    }
    final rect = Rect.fromCircle(center: _center, radius: _r0);
    for (final a in arcs) {
      final start = a.m0 / 1440 * math.pi * 2 - math.pi / 2;
      final sweep = (a.m1 - a.m0) / 1440 * math.pi * 2;
      var frac = 1.0;
      if (a.drawIn) {
        final t = ((progress - a.order * 45) / 700).clamp(0.0, 1.0);
        frac = PlannerMotion.snapCurve.transform(t);
      }
      if (frac <= 0) continue;
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = a.width
        ..color = a.color.withValues(alpha: a.color.a * a.opacity);
      final path = Path()..addArc(rect, start, sweep * frac);
      if (a.dash == null) {
        canvas.drawPath(path, p);
      } else {
        for (final mtr in path.computeMetrics()) {
          var d = 0.0;
          while (d < mtr.length) {
            canvas.drawPath(mtr.extractPath(d, math.min(d + a.dash![0], mtr.length)), p);
            d += a.dash![0] + a.dash![1];
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(_DialPainter old) => true;
}

class _HandPainter extends CustomPainter {
  _HandPainter(this.turn, this.color);
  final double turn;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final a = turn * math.pi * 2 - math.pi / 2;
    final dir = Offset(math.cos(a), math.sin(a));
    const cen = Offset(_size / 2, _size / 2);
    canvas.drawLine(
        cen + dir * 106,
        cen + dir * 150,
        Paint()
          ..color = color
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round);
    canvas.drawCircle(cen + dir * 150, 4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_HandPainter old) => old.turn != turn || old.color != color;
}
