import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../app/theme/planner_theme.dart';
import '../domain/task.dart';
import '../domain/time.dart';
import 'controls.dart';
import 'surfaces.dart';

/// Everything a [TaskBlock] needs to draw one state (README 7.1).
class TaskBlockLook {
  const TaskBlockLook({
    required this.task,
    required this.height,
    this.isCurrent = false,
    this.isNext = false,
    this.missed = false,
    this.staged = false,
    this.visuallyDone = false,
    this.sweepScale = false,
    this.sweepVisible = false,
    this.checkPop = false,
    this.fresh = false,
    this.canCheck = true,
    this.canSwipe = false,
    this.elapsed = 0,
    this.windDownMinutes = 0,
  });

  final Task task;
  final double height;
  final bool isCurrent, isNext, missed, staged;

  /// Done and past the sweep (prototype `vDone`).
  final bool visuallyDone;

  /// Sweep fill scaled across (phases a and b) and visible (phase a).
  final bool sweepScale, sweepVisible;

  /// Check scales to 1.18 during the sweep.
  final bool checkPop;
  final bool fresh;
  final bool canCheck, canSwipe;

  /// 0..1 of the current block that has elapsed.
  final double elapsed;

  /// Minutes of this block inside wind-down (overflow stripes).
  final int windDownMinutes;

  /// Full category colour only for current and next.
  bool get full => (isCurrent || isNext) && !visuallyDone && !missed && !staged;
  bool get tall => height >= 60;
}

class TaskBlock extends StatefulWidget {
  const TaskBlock({
    super.key,
    required this.look,
    required this.onOpen,
    required this.onComplete,
    this.onReschedule,
  });

  final TaskBlockLook look;
  final VoidCallback onOpen;

  /// Called by the check, a swipe past 70px, or the Complete action.
  final void Function({required bool fromSwipe}) onComplete;
  final VoidCallback? onReschedule;

  @override
  State<TaskBlock> createState() => _TaskBlockState();
}

class _TaskBlockState extends State<TaskBlock> with SingleTickerProviderStateMixin {
  double _dx = 0; // raw drag distance, 0..140
  bool _dragging = false;
  late final AnimationController _back = AnimationController(vsync: this);
  double _backFrom = 0;

  @override
  void initState() {
    super.initState();
    _back.addListener(() => setState(() {
          _dx = _backFrom *
              (1 - PlannerMotion.swipeReturnCurve.transform(_back.value));
        }));
  }

  @override
  void dispose() {
    _back.dispose();
    super.dispose();
  }

  /// 1:1 to 80px, then 0.35×, capped at 140 raw.
  double get _eased => _dx < 80 ? _dx : 80 + (_dx - 80) * 0.35;

  void _dragStart(DragStartDetails d) {
    if (!widget.look.canSwipe) return;
    _back.stop();
    _dragging = true;
  }

  void _dragUpdate(DragUpdateDetails d) {
    if (!_dragging) return;
    setState(() => _dx = (_dx + d.delta.dx).clamp(0, 140).toDouble());
  }

  void _dragEnd(DragEndDetails d) {
    if (!_dragging) return;
    _dragging = false;
    final done = _dx > 70;
    _backFrom = _dx;
    _back
      ..duration = PlannerMotion.ms(context, 560)
      ..forward(from: 0);
    if (done) widget.onComplete(fromSwipe: true);
  }

  String _semantics(TaskBlockLook l) {
    final t = l.task;
    final state = l.visuallyDone || t.done
        ? ', done'
        : l.missed
            ? ', missed'
            : l.isCurrent
                ? ', in progress'
                : l.isNext
                    ? ', next'
                    : '';
    return '${t.title}, ${fmt(t.start!)} to ${fmt(t.end!)}$state';
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        // Tall vs short is decided by the height actually laid out, so a
        // block growing during placement never overflows mid-animation.
        builder: (context, box) => _build(
            context, box.maxHeight.isFinite ? box.maxHeight >= 60 : widget.look.tall),
      );

  Widget _build(BuildContext context, bool tall) {
    final c = PlannerColors.of(context);
    final l = widget.look;
    final t = l.task;
    final cat = t.cat;
    final full = l.full;
    final done = l.visuallyDone;
    final ms = PlannerMotion.ms;
    final bg = done
        ? c.bg
        : l.missed
            ? Colors.transparent
            : full
                ? cat.color
                : cat.tint(c);
    final titleC = done
        ? c.t3
        : l.missed
            ? c.t2
            : full
                ? cat.ink
                : c.tx;
    final subC = full ? cat.ink.withValues(alpha: 0.78) : c.t3;
    final chip = l.isCurrent && !done
        ? 'NOW'
        : l.isNext && !done
            ? 'NEXT'
            : l.missed
                ? 'MISSED'
                : t.recurrence != null
                    ? 'REPEATS'
                    : '';
    final ring = done
        ? Border.all(color: c.ln, width: 1)
        : l.staged || l.fresh
            ? Border.all(color: cat.color, width: 1.5)
            : null;
    final ovH = !done && l.windDownMinutes > 0
        ? l.height * l.windDownMinutes / (t.end! - t.start!)
        : 0.0;

    final content = Stack(children: [
      // Dashed outline when missed.
      Positioned.fill(
        child: AnimatedOpacity(
          opacity: l.missed ? 1 : 0,
          duration: ms(context, 300),
          child: DashedBox(color: c.t3),
        ),
      ),
      // Elapsed shade grows each second on the current block.
      Positioned.fill(
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: l.isCurrent && full ? l.elapsed.clamp(0.0, 1.0) : 0,
          child: const ColoredBox(color: Color(0x2E000000)),
        ),
      ),
      // Overflow into wind-down: category stripes with a WIND-DOWN label.
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: AnimatedContainer(
          duration: ms(context, 400),
          height: ovH,
          child: Stack(children: [
            Positioned.fill(
              child: CustomPaint(
                painter: HatchPainter(
                  color: full ? const Color(0x59FFFFFF) : cat.color.withValues(alpha: 0.6),
                  width: 2,
                  period: 6,
                ),
              ),
            ),
            if (l.windDownMinutes >= 20 && !done)
              Positioned(
                left: 14,
                bottom: 5,
                child: Text('WIND-DOWN',
                    style: PlannerType.stateLabel(size: 9, tracking: 0.08, color: subC)),
              ),
          ]),
        ),
      ),
      // Completion sweep: scaleX 0 → 1 over 380 Snap.
      Positioned.fill(
        child: AnimatedOpacity(
          opacity: l.sweepVisible ? 0.9 : 0,
          duration: ms(context, 520),
          child: _Sweep(
            on: l.sweepScale,
            color: full ? const Color(0x57FFFFFF) : cat.color,
          ),
        ),
      ),
      // Title, meta and chip.
      Positioned.fill(
        right: 48,
        child: Semantics(
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onOpen,
            child: Padding(
              padding: EdgeInsets.only(left: 14, top: tall ? 11 : 0),
              child: Row(
                crossAxisAlignment: tall ? CrossAxisAlignment.start : CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      mainAxisAlignment:
                          tall ? MainAxisAlignment.start : MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          AnimatedContainer(
                            duration: ms(context, 300),
                            width: full ? 0 : 8,
                            height: 8,
                            margin: EdgeInsets.only(right: full ? 0 : 8),
                            decoration: BoxDecoration(
                              color: cat.color.withValues(alpha: full ? 0 : done ? 0.45 : 1),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          Flexible(
                            child: AnimatedDefaultTextStyle(
                              duration: ms(context, 400),
                              style: PlannerType.taskTitle(color: titleC).copyWith(
                                decoration: done ? TextDecoration.lineThrough : null,
                                decorationThickness: 1,
                                decorationColor: c.t3,
                              ),
                              child: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                            ),
                          ),
                          if (chip.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(chip,
                                style: PlannerType.stateLabel(
                                    size: 9.5, tracking: 0.08, color: full ? cat.ink : c.t2)),
                          ],
                        ]),
                        if (tall) ...[
                          const SizedBox(height: 3),
                          Text('${fmt(t.start!)} → ${fmt(t.end!)}',
                              style: PlannerType.time(size: 12, color: subC)),
                        ],
                      ],
                    ),
                  ),
                  if (!tall)
                    Text(dur(t.end! - t.start!), style: PlannerType.time(size: 12, color: subC)),
                ],
              ),
            ),
          ),
        ),
      ),
      // The check (22px visible, 44px target).
      Positioned(
        right: 2,
        top: 0,
        width: 44,
        height: tall ? 48 : 44,
        child: IgnorePointer(
          ignoring: !l.canCheck,
          child: AnimatedOpacity(
            opacity: l.canCheck ? 1 : 0,
            duration: ms(context, 200),
            child: Pressable(
              onTap: () => widget.onComplete(fromSwipe: false),
              label: done ? 'Mark ${t.title} not done' : 'Complete ${t.title}',
              pressedScale: 0.86,
              excludeChildSemantics: true,
              child: Center(
                child: _Check(
                  done: done,
                  pop: l.checkPop,
                  border: done ? c.t2 : full ? cat.ink : c.t3,
                  fill: done ? c.t2 : Colors.transparent,
                  tick: c.bg,
                ),
              ),
            ),
          ),
        ),
      ),
    ]);

    final face = AnimatedContainer(
      duration: ms(context, 400),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      foregroundDecoration: ring == null
          ? null
          : BoxDecoration(border: ring, borderRadius: BorderRadius.circular(4)),
      clipBehavior: Clip.antiAlias,
      child: content,
    );

    return Semantics(
      container: true,
      label: _semantics(l),
      hint: l.missed ? 'Double-tap to decide.' : 'Double-tap for details.',
      onTap: widget.onOpen,
      customSemanticsActions: {
        if (!t.done && l.canCheck)
          const CustomSemanticsAction(label: 'Complete'): () => widget.onComplete(fromSwipe: false),
        if (widget.onReschedule != null)
          const CustomSemanticsAction(label: 'Reschedule'): widget.onReschedule!,
      },
      child: GestureDetector(
        excludeFromSemantics: true,
        onHorizontalDragStart: l.canSwipe ? _dragStart : null,
        onHorizontalDragUpdate: l.canSwipe ? _dragUpdate : null,
        onHorizontalDragEnd: l.canSwipe ? _dragEnd : null,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(children: [
            // Reveal layer: tint plus the category-coloured DONE label.
            if (_dx > 0)
              Positioned.fill(
                child: ColoredBox(
                  color: cat.tint(c),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 14),
                      child: Text('DONE',
                          style: PlannerType.stateLabel(size: 11, tracking: 0.08, color: cat.color)),
                    ),
                  ),
                ),
              ),
            Positioned.fill(
              child: Transform.translate(offset: Offset(_eased, 0), child: face),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Sweep extends StatelessWidget {
  const _Sweep({required this.on, required this.color});
  final bool on;
  final Color color;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(end: on ? 1 : 0),
        duration: PlannerMotion.ms(context, 380),
        curve: PlannerMotion.snapCurve,
        builder: (context, v, _) => FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: v,
          child: ColoredBox(color: color),
        ),
      );
}

/// The 22px check: scale to 1.18 during the sweep, tick draws 300ms after
/// a 200ms delay.
class _Check extends StatelessWidget {
  const _Check({
    required this.done,
    required this.pop,
    required this.border,
    required this.fill,
    required this.tick,
  });
  final bool done, pop;
  final Color border, fill, tick;

  @override
  Widget build(BuildContext context) {
    final ms = PlannerMotion.ms;
    return AnimatedScale(
      scale: pop ? 1.18 : 1,
      duration: ms(context, 520),
      curve: const Cubic(0.34, 1.6, 0.55, 1),
      child: AnimatedContainer(
        duration: ms(context, 240),
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: fill,
          border: Border.all(color: border, width: 1.5),
        ),
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: done || pop ? 1 : 0),
          duration: ms(context, done || pop ? 500 : 200),
          curve: done || pop
              ? const Interval(0.4, 1, curve: PlannerMotion.snapCurve)
              : PlannerMotion.snapCurve,
          builder: (context, v, _) => CustomPaint(painter: _TickPainter(v, tick)),
        ),
      ),
    );
  }
}

class _TickPainter extends CustomPainter {
  _TickPainter(this.v, this.color);
  final double v;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (v <= 0) return;
    // M3 7.2 l2.6 2.6 L11 4.4 in a 14px box, centred in the 22px circle.
    final o = Offset((size.width - 14) / 2 - 1.5, (size.height - 14) / 2 - 1.5);
    final path = Path()
      ..moveTo(o.dx + 3, o.dy + 7.2)
      ..lineTo(o.dx + 5.6, o.dy + 9.8)
      ..lineTo(o.dx + 11, o.dy + 4.4);
    final m = path.computeMetrics().first;
    canvas.drawPath(
      m.extractPath(0, m.length * v),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.9
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_TickPainter old) => old.v != v || old.color != color;
}
