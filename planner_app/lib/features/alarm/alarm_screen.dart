import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../app/theme/category_style.dart';
import '../../app/theme/planner_type.dart';
import '../../data/alarm_prefs.dart';
import '../../domain/time.dart';
import '../../widgets/controls.dart';
import 'alarm_backgrounds.dart';
import 'alarm_engine.dart';

/// The full-screen task alarm: the chosen background, a big clock, the task,
/// and Done, Snooze and Start now (tapped, or slid when "Slide to confirm"
/// is on). [preview] renders it inert for the customise page.
class AlarmScreen extends StatefulWidget {
  const AlarmScreen({
    super.key,
    required this.alarm,
    required this.look,
    required this.prefs,
    this.onDone,
    this.onSnooze,
    this.onStart,
    this.preview = false,
    this.reduced = false,
  });

  final PlannedAlarm alarm;
  final AlarmLook look;
  final AlarmPrefs prefs;
  final VoidCallback? onDone, onSnooze, onStart;
  final bool preview, reduced;

  @override
  State<AlarmScreen> createState() => _AlarmScreenState();
}

class _AlarmScreenState extends State<AlarmScreen> {
  Timer? _tick;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    if (!widget.preview) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => _now = DateTime.now()));
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  TextStyle _clock(double size) => switch (widget.look.font) {
        ClockFont.bricolage => PlannerType.bricolageW(size, 600, height: 1, tracking: -0.04, color: Colors.white),
        ClockFont.geist => PlannerType.numeral(size, color: Colors.white),
        ClockFont.mono => PlannerType.time(size: size * 0.86, weight: 500, color: Colors.white),
      };

  @override
  Widget build(BuildContext context) {
    final a = widget.alarm;
    final l = widget.look;
    final shown = widget.preview ? a.at : _now;
    final left = l.align == AlarmAlign.left;
    final cross = left ? CrossAxisAlignment.start : CrossAxisAlignment.center;
    final ta = left ? TextAlign.left : TextAlign.center;
    const shadow = [Shadow(blurRadius: 18, color: Color(0x73000000))];
    final day = dayOf(shown);
    Widget text(String s, TextStyle st) => Text(s, textAlign: ta, style: st.copyWith(shadows: shadow));

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Material(
        color: Colors.black,
        child: Stack(fit: StackFit.expand, children: [
          ExcludeSemantics(child: AlarmBackground(look: l, cat: a.cat, reduced: widget.reduced)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 20, 28, 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Text('TASK ALARM', style: PlannerType.stateLabel(size: 11, color: Colors.white70)),
                  const Spacer(),
                  CatSquare(a.cat.color, size: 9),
                  const SizedBox(width: 6),
                  Text(a.cat.label, style: PlannerType.ui(13, color: Colors.white70)),
                ]),
                const Spacer(flex: 2),
                Column(crossAxisAlignment: cross, children: [
                  Semantics(
                    label: 'It is ${fmt(shown.hour * 60 + shown.minute)}',
                    excludeSemantics: true,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: text(fmt(shown.hour * 60 + shown.minute), _clock(l.size.points)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  text(dayLabel(day), PlannerType.ui(15, color: Colors.white70)),
                  const SizedBox(height: 30),
                  if (l.showTitle)
                    Semantics(
                      header: true,
                      child: text(a.title, PlannerType.bricolage600(32, height: 1.1, tracking: -0.015, color: Colors.white)),
                    ),
                  if (l.showRange && a.range.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    text(a.range, PlannerType.time(size: 15, color: Colors.white.withValues(alpha: 0.8))),
                  ],
                  if (l.message.trim().isNotEmpty) ...[
                    const SizedBox(height: 14),
                    text(l.message.trim(), PlannerType.bricolageW(19, 500, height: 1.3, color: Colors.white)),
                  ],
                  if (l.showNext && a.next.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    text(a.next, PlannerType.ui(13, color: Colors.white60)),
                  ],
                ]),
                const Spacer(flex: 3),
                IgnorePointer(
                  ignoring: widget.preview,
                  child: widget.prefs.slide ? _slideActions() : _tapActions(),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  String get _snoozeLabel => 'Snooze ${widget.prefs.snoozeMinutes} min';

  Widget _tapActions() => Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(child: _Glass(label: _snoozeLabel, onTap: widget.onSnooze)),
          const SizedBox(width: 10),
          Expanded(child: _Glass(label: 'Start now', onTap: widget.onStart)),
        ]),
        const SizedBox(height: 12),
        Pressable(
          onTap: widget.onDone,
          label: 'Done, mark ${widget.alarm.title} complete',
          excludeChildSemantics: true,
          child: Container(
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32)),
            child: Text('Done', style: PlannerType.ui(18, weight: 600, color: Colors.black)),
          ),
        ),
      ]);

  Widget _slideActions() => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _SlideToAnswer(
          snoozeLabel: _snoozeLabel,
          accent: widget.alarm.cat.color,
          onDone: widget.onDone,
          onSnooze: widget.onSnooze,
        ),
        const SizedBox(height: 10),
        _Glass(label: 'Start now', onTap: widget.onStart, height: 48),
      ]);
}

class _Glass extends StatelessWidget {
  const _Glass({required this.label, this.onTap, this.height = 52});
  final String label;
  final VoidCallback? onTap;
  final double height;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        label: label,
        excludeChildSemantics: true,
        child: Container(
          height: height,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(height / 2),
            border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
          ),
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: PlannerType.ui(15, weight: 500, color: Colors.white)),
        ),
      );
}

/// Slide right for Done, left to snooze. The knob springs back unless it
/// passes 38% of the track. Screen readers get both as actions.
class _SlideToAnswer extends StatefulWidget {
  const _SlideToAnswer({required this.snoozeLabel, required this.accent, this.onDone, this.onSnooze});
  final String snoozeLabel;
  final Color accent;
  final VoidCallback? onDone, onSnooze;

  @override
  State<_SlideToAnswer> createState() => _SlideToAnswerState();
}

class _SlideToAnswerState extends State<_SlideToAnswer> with SingleTickerProviderStateMixin {
  late final _back = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
  double _dx = 0, _from = 0, _travel = 1;
  bool _fired = false;

  @override
  void initState() {
    super.initState();
    _back.addListener(() => setState(() => _dx = _from * (1 - Curves.easeOutBack.transform(_back.value))));
  }

  @override
  void dispose() {
    _back.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        const knob = 60.0, h = 72.0;
        final travel = _travel = (box.maxWidth - knob) / 2 - 6;
        final q = (_dx / travel).clamp(-1.0, 1.0);
        return Semantics(
          label: 'Slide right for Done, left to snooze',
          excludeSemantics: true,
          customSemanticsActions: {
            if (widget.onDone != null) const CustomSemanticsAction(label: 'Done'): widget.onDone!,
            if (widget.onSnooze != null) CustomSemanticsAction(label: widget.snoozeLabel): widget.onSnooze!,
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (_) => _back.stop(),
            onHorizontalDragUpdate: (d) {
              if (_fired) return;
              setState(() => _dx = (_dx + d.delta.dx).clamp(-travel, travel));
            },
            onHorizontalDragEnd: (_) {
              if (_fired) return;
              // Measured now: the last frame may predate the last move.
              final q = _dx / _travel;
              if (q > 0.38 && widget.onDone != null) {
                _fired = true;
                HapticFeedback.mediumImpact();
                widget.onDone!();
              } else if (q < -0.38 && widget.onSnooze != null) {
                _fired = true;
                HapticFeedback.selectionClick();
                widget.onSnooze!();
              } else {
                _from = _dx;
                _back.forward(from: 0);
              }
            },
            child: Container(
              height: h,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(h / 2),
                color: Colors.white.withValues(alpha: 0.12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
              ),
              child: Stack(alignment: Alignment.center, children: [
                Positioned(
                  left: 26,
                  child: Opacity(
                    opacity: (1 + q * 1.4).clamp(0.25, 1.0),
                    child: Text('‹ ${widget.snoozeLabel}', style: PlannerType.ui(14, color: Colors.white70)),
                  ),
                ),
                Positioned(
                  right: 26,
                  child: Opacity(
                    opacity: (1 - q * 1.4).clamp(0.25, 1.0),
                    child: Text('Done ›', style: PlannerType.ui(14, weight: 600, color: Colors.white)),
                  ),
                ),
                Transform.translate(
                  offset: Offset(_dx, 0),
                  child: Container(
                    width: knob,
                    height: knob,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color.lerp(Colors.white, widget.accent, q.abs() * 0.6),
                      boxShadow: [BoxShadow(color: widget.accent.withValues(alpha: 0.5), blurRadius: 24)],
                    ),
                  ),
                ),
              ]),
            ),
          ),
        );
      });
}
