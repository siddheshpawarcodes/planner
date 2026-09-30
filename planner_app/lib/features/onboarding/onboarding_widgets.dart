import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/planner_theme.dart';
import '../../domain/base_day.dart';
import '../../domain/layout.dart';
import '../../domain/onboarding.dart';
import '../../domain/routine.dart';
import '../../domain/time.dart';
import '../../widgets/controls.dart';
import '../../widgets/icons.dart';
import '../../widgets/surfaces.dart';

/// Five 3px progress segments; each fills with `tx` on Settle 520.
class ObSegments extends StatelessWidget {
  const ObSegments({super.key, required this.step});
  final int step;

  @override
  Widget build(BuildContext context) {
    final c = PlannerColors.of(context);
    return Semantics(
      label: 'Question ${math.min(step, 4) + 1} of 5',
      child: Row(children: [
        for (var i = 0; i < 5; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: Container(
              height: 3,
              decoration: BoxDecoration(color: c.ln, borderRadius: BorderRadius.circular(2)),
              clipBehavior: Clip.antiAlias,
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: i <= math.min(step, 4) ? 1 : 0),
                duration: PlannerMotion.ms(context, 520),
                curve: PlannerMotion.settleCurve,
                builder: (context, v, _) => FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: v.clamp(0, 1),
                  child: ColoredBox(color: c.tx),
                ),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

/// −/+ 15 minute buttons around the Geist 300 88 readout. The readout is a
/// live region; keyboard and screen readers use the buttons.
class ObTimeReadout extends StatelessWidget {
  const ObTimeReadout({
    super.key,
    required this.value,
    required this.question,
    required this.onMinus,
    required this.onPlus,
  });
  final int value;
  final String question;
  final VoidCallback onMinus, onPlus;

  @override
  Widget build(BuildContext context) {
    final c = PlannerColors.of(context);
    Widget btn(String glyph, String label, VoidCallback onTap) => Pressable(
          onTap: onTap,
          label: label,
          pressedScale: 0.92,
          excludeChildSemantics: true,
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c.ln)),
            child: Text(glyph, style: PlannerType.ui(20, weight: 400, color: c.t2)),
          ),
        );
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      btn('−', '15 minutes earlier', onMinus),
      const SizedBox(width: 14),
      SizedBox(
        width: 220,
        height: 88,
        child: Semantics(
          liveRegion: true,
          label: '$question ${fmt(value)}',
          excludeSemantics: true,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(fmt(value), style: PlannerType.numeral(88, color: c.tx).copyWith(height: 1)),
          ),
        ),
      ),
      const SizedBox(width: 14),
      btn('+', '15 minutes later', onPlus),
    ]);
  }
}

/// The draggable ruler: 2 px per minute, 15-minute ticks, hour labels, a
/// fixed `tx` marker in the middle and masked edges. Dragging snaps to 5
/// minutes (see [OnboardingDraft.drag]).
class ObRuler extends StatefulWidget {
  const ObRuler({super.key, required this.value, required this.onDrag});
  final int value;

  /// (value when the drag started, horizontal distance since then).
  final void Function(int from, double dx) onDrag;

  @override
  State<ObRuler> createState() => _ObRulerState();
}

class _ObRulerState extends State<ObRuler> {
  double _x0 = 0;
  int _v0 = 0;

  @override
  Widget build(BuildContext context) {
    final c = PlannerColors.of(context);
    return ExcludeSemantics(
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (d) {
            _x0 = d.localPosition.dx;
            _v0 = widget.value;
          },
          onHorizontalDragUpdate: (d) => widget.onDrag(_v0, d.localPosition.dx - _x0),
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (r) => const LinearGradient(
              colors: [Color(0x00000000), Color(0xFF000000), Color(0xFF000000), Color(0x00000000)],
              stops: [0, 0.22, 0.78, 1],
            ).createShader(r),
            child: CustomPaint(
              size: const Size(320, 70),
              painter: _RulerPainter(widget.value, c.tx, c.t3, PlannerType.time(size: 10, weight: 500, color: c.t3)),
            ),
          ),
        ),
      ),
    );
  }
}

class _RulerPainter extends CustomPainter {
  _RulerPainter(this.v, this.tx, this.t3, this.label);
  final int v;
  final Color tx, t3;
  final TextStyle label;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    final p = Paint();
    final st = ((v - 150) / 15).ceil() * 15;
    for (var m = st; m <= v + 150; m += 15) {
      final hr = m % 60 == 0;
      final x = 160 + (m - v) * 2 - 0.5;
      p.color = hr ? tx : t3;
      canvas.drawRect(Rect.fromLTWH(x, 10, 1, hr ? 18 : (m % 30 == 0 ? 12 : 7)), p);
      if (hr) {
        final tp = TextPainter(
          text: TextSpan(text: fmt(m).substring(0, 2), style: label),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x + 0.5 - tp.width / 2, 36));
      }
    }
    p.color = tx;
    canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(159, 4, 2, 30), const Radius.circular(1)), p);
  }

  @override
  bool shouldRepaint(_RulerPainter old) => old.v != v || old.tx != tx || old.t3 != t3;
}

/// The live 24h bar: night, protected hatch, work band, commitments and
/// dashed open time for the first weekday, with a `tx` marker at the value
/// being set. Segments glide on Settle 420 as answers change.
class ObDayBar extends StatelessWidget {
  const ObDayBar({super.key, required this.draft, required this.day, required this.width});
  final OnboardingDraft draft;
  final int day;
  final double width;

  @override
  Widget build(BuildContext context) {
    final c = PlannerColors.of(context);
    final r = draft.preview;
    final k = width / 1440;
    final d = PlannerMotion.ms(context, 420);
    final seq = buildDay(day, r, const []).seq.where((x) => x.kind != ItemKind.marker);
    final segs = <Widget>[];
    void seg(String key, int s, int e, Widget child) => segs.add(AnimatedPositioned(
          key: ValueKey(key),
          duration: d,
          curve: PlannerMotion.settleCurve,
          left: s * k,
          width: math.max(1, (e - s) * k - 1),
          top: 0,
          bottom: 0,
          child: child,
        ));
    Widget fill(Color col) =>
        DecoratedBox(decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(2)));
    seg('night0', 0, r.wake + 1, fill(c.s1));
    var open = 0;
    for (final x in seq) {
      switch (x.kind) {
        case ItemKind.fixed:
          seg(x.id, x.start, x.end, fill(x.cat!.color));
        case ItemKind.protected:
          seg(x.id, x.start, x.end, Hatch(color: c.t3, period: 4, radius: 2));
        case ItemKind.open:
          seg('open${open++}', x.start, x.end, DashedBox(color: c.t2, radius: 2));
        default:
      }
    }
    if (r.sleep < 1440) seg('night1', r.sleep, 1441, fill(c.s1));
    final v = draft.value;
    final legend = draft.noWork
        ? 'Your own time: everything outside sleep and meals'
        : 'Office ${fmt(draft.workStart)} → ${fmt(draft.workEnd)}';
    return Semantics(
      label: 'Your day. $legend',
      excludeSemantics: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Text('Your day', style: PlannerType.ui(12, weight: 400, color: c.t2)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(legend,
                textAlign: TextAlign.right,
                maxLines: 2,
                style: PlannerType.ui(12, weight: 400, color: c.t3)),
          ),
        ]),
        const SizedBox(height: 8),
        SizedBox(
          height: 16,
          child: Stack(clipBehavior: Clip.none, children: [
            ...segs,
            AnimatedPositioned(
              duration: PlannerMotion.ms(context, 300),
              curve: PlannerMotion.settleCurve,
              left: v == null ? -10 : math.min(v, 1440) * k - 1,
              top: -5,
              bottom: -5,
              width: 2,
              child: AnimatedOpacity(
                opacity: v == null ? 0 : 1,
                duration: PlannerMotion.ms(context, 300),
                child: DecoratedBox(
                    decoration: BoxDecoration(color: c.tx, borderRadius: BorderRadius.circular(1))),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          for (final h in const ['00', '06', '12', '18', '24'])
            Text(h, style: PlannerType.time(size: 10, weight: 500, color: c.t3)),
        ]),
      ]),
    );
  }
}

/// A commitment toggle row: category square, title, rule and time, check.
class ObCommitRow extends StatelessWidget {
  const ObCommitRow({super.key, required this.commitment, required this.onTap});
  final Commitment commitment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PlannerColors.of(context);
    final cm = commitment;
    final d = PlannerMotion.ms(context, 200);
    return Pressable(
      onTap: onTap,
      toggled: cm.on,
      label: '${cm.title}, ${cm.label.replaceAll('→', 'to')}',
      radius: 4,
      pressedScale: 0.985,
      excludeChildSemantics: true,
      child: AnimatedContainer(
        duration: d,
        constraints: const BoxConstraints(minHeight: 60),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: cm.on ? c.s1 : c.s1.withValues(alpha: 0),
          border: Border.all(color: cm.on ? c.tx : c.ln),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(children: [
          CatSquare(cm.cat.color, size: 10),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(cm.title, style: PlannerType.bricolage600(15, height: 1.2, color: c.tx)),
              const SizedBox(height: 2),
              Text(cm.label, style: PlannerType.time(size: 12, color: c.t3)),
            ]),
          ),
          const SizedBox(width: 12),
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c.t3, width: 1.5)),
            alignment: Alignment.center,
            child: AnimatedOpacity(
              opacity: cm.on ? 1 : 0,
              duration: d,
              child: CustomPaint(size: const Size.square(14), painter: _TickPainter(c.tx)),
            ),
          ),
        ]),
      ),
    );
  }
}

class _TickPainter extends CustomPainter {
  _TickPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..moveTo(3, 7.2)
        ..relativeLineTo(2.6, 2.6)
        ..lineTo(11, 4.4),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.9
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_TickPainter old) => old.color != color;
}

/// "Add your own": title, start chip, length and days.
class ObCustomForm extends StatelessWidget {
  const ObCustomForm({
    super.key,
    required this.value,
    required this.controller,
    required this.onEdit,
    required this.onAdd,
    required this.onCancel,
  });
  final CustomCommitment value;
  final TextEditingController controller;
  /// Edits apply to the latest form state, never a stale copy.
  final void Function(CustomCommitment Function(CustomCommitment c) f) onEdit;
  final VoidCallback onAdd, onCancel;

  @override
  Widget build(BuildContext context) {
    final c = PlannerColors.of(context);
    final cu = value;
    Widget chip(String label, bool on, VoidCallback onTap, {bool mono = false}) =>
        PlannerChip(label: label, selected: on, onTap: onTap, height: 34, filledWhenIdle: true, mono: mono);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: c.s1, borderRadius: BorderRadius.circular(4)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('What is it?', style: PlannerType.ui(12, color: c.t2)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
          onChanged: (v) => onEdit((c) => c.copyWith(title: v)),
          onSubmitted: (_) => onAdd(),
          style: PlannerType.ui(15, color: c.tx),
          cursorColor: c.tx,
          decoration: InputDecoration(
            hintText: 'Evening walk',
            hintStyle: PlannerType.ui(15, color: c.t3),
            isDense: true,
            filled: true,
            fillColor: c.bg,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: c.ln)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4), borderSide: BorderSide(color: c.t3)),
          ),
        ),
        const SizedBox(height: 4),
        Wrap(spacing: 6, children: [
          for (final m in CustomCommitment.starts)
            chip(fmt(m), cu.at == m, () => onEdit((c) => c.copyWith(at: m)), mono: true),
        ]),
        Wrap(spacing: 6, children: [
          for (final m in CustomCommitment.lengths)
            chip(dur(m), cu.length == m, () => onEdit((c) => c.copyWith(length: m))),
          for (final r in CustomCommitment.dayRules)
            chip(r.label, cu.days == r, () => onEdit((c) => c.copyWith(days: r))),
        ]),
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextPill(label: 'Cancel', onTap: onCancel, height: 40),
          const SizedBox(width: 8),
          PrimaryPill(label: 'Add', height: 40, onTap: cu.title.trim().isEmpty ? null : onAdd),
        ]),
      ]),
    );
  }
}

/// The dashed "Add your own" button.
class ObAddOwn extends StatelessWidget {
  const ObAddOwn({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PlannerColors.of(context);
    return Pressable(
      onTap: onTap,
      label: 'Add your own',
      radius: 4,
      pressedScale: 0.985,
      excludeChildSemantics: true,
      child: SizedBox(
        height: 48,
        child: DashedBox(
          color: c.ln,
          radius: 4,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            PlannerIcon(PIcon.plus, size: 16, color: c.t2, stroke: 1.6),
            const SizedBox(width: 8),
            Text('Add your own', style: PlannerType.ui(13, color: c.t2)),
          ]),
        ),
      ),
    );
  }
}

/// One row of the assembly: it rises 14px (and from 0.98) on Spring while it
/// fades in.
class ObAssemblyRow extends StatelessWidget {
  const ObAssemblyRow({super.key, required this.item, required this.on});
  final TimelineItem item;
  final bool on;

  static double heightOf(TimelineItem x) {
    final d = x.end - x.start;
    return switch (x.kind) {
      ItemKind.marker => 22,
      ItemKind.fixed => d > 90 ? 40 : math.max(24, d * 0.4),
      _ => math.max(22, d * 0.38),
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = PlannerColors.of(context);
    final x = item;
    final meta = '${fmt(x.start)} → ${fmt(x.end)}';
    final content = switch (x.kind) {
      ItemKind.marker => Row(children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c.t3, width: 1.5)),
          ),
          const SizedBox(width: 10),
          Text(x.title, style: PlannerType.ui(13, color: c.t2)),
        ]),
      ItemKind.fixed => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: x.cat!.tintAt(c, c.isDark ? 0.3 : 0.24),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(children: [
            Expanded(child: Text(x.title, maxLines: 1, style: PlannerType.ui(13, color: c.tx))),
            Text(meta, style: PlannerType.time(size: 11, color: c.t2)),
          ]),
        ),
      ItemKind.protected => Stack(fit: StackFit.expand, children: [
          Hatch(color: c.ln, period: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(x.title, maxLines: 1, style: PlannerType.ui(12, color: c.t3)),
            ),
          ),
        ]),
      _ => DashedBox(
          color: c.t3,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              Expanded(child: Text('Your time', style: PlannerType.bricolage600(14, color: c.tx))),
              Text(meta, style: PlannerType.time(size: 11, color: c.t2)),
            ]),
          ),
        ),
    };
    final label = x.kind == ItemKind.marker
        ? '${x.title} ${fmt(x.start)}'
        : '${x.kind == ItemKind.open ? 'Your time' : x.title}, ${fmt(x.start)} to ${fmt(x.end)}';
    return ExcludeSemantics(
      excluding: !on,
      child: Semantics(
        label: label,
        excludeSemantics: true,
        child: AnimatedOpacity(
          opacity: on ? 1 : 0,
          duration: PlannerMotion.ms(context, 320),
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: on ? 1 : 0),
            duration: PlannerMotion.of(context, PlannerMotion.spring),
            curve: PlannerMotion.springCurve,
            builder: (context, v, child) => Transform.translate(
              offset: Offset(0, 14 * (1 - v)),
              child: Transform.scale(scale: 0.98 + 0.02 * v, child: child),
            ),
            child: SizedBox(
              height: heightOf(x),
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SizedBox(
                  width: 40,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      height: 22,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(fmt(x.start), style: PlannerType.time(size: 11, weight: 500, color: c.t3)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: content),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
