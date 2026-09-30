import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../app/theme/planner_theme.dart';
import 'icons.dart';

/// Base interactive surface (README 7.5): pressed = Snap scale, focused =
/// 2px `tx` outline with 2px offset, hover for desktop, Enter/Space activate.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.label,
    this.pressedScale = 0.97,
    this.radius = 999,
    this.selected,
    this.toggled,
    this.button = true,
    this.focusable = true,
    this.excludeChildSemantics = false,
    this.hint,
    this.customActions,
    this.onHover,
    this.cursor,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? label;
  final String? hint;
  final double pressedScale;
  final double radius;
  final bool? selected;
  final bool? toggled;
  final bool button;
  final bool focusable;
  final bool excludeChildSemantics;
  final Map<CustomSemanticsAction, VoidCallback>? customActions;
  final ValueChanged<bool>? onHover;
  final MouseCursor? cursor;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false, _focus = false;

  bool get _enabled => widget.onTap != null;

  @override
  Widget build(BuildContext context) {
    final c = PlannerColors.of(context);
    final d = PlannerMotion.of(context, PlannerMotion.snap);
    Widget child = AnimatedScale(
      scale: _down ? widget.pressedScale : 1,
      duration: d,
      curve: PlannerMotion.snapCurve,
      child: widget.child,
    );
    child = DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.radius + 2),
        border: _focus
            ? Border.all(color: c.tx, width: 2, strokeAlign: BorderSide.strokeAlignOutside + 1)
            : null,
      ),
      child: child,
    );
    return Semantics(
      container: true,
      button: widget.button && widget.toggled == null,
      toggled: widget.toggled,
      selected: widget.selected,
      enabled: _enabled,
      label: widget.label,
      hint: widget.hint,
      customSemanticsActions: widget.customActions,
      excludeSemantics: widget.excludeChildSemantics,
      onTap: widget.onTap,
      child: FocusableActionDetector(
        enabled: _enabled && widget.focusable,
        onShowFocusHighlight: (v) => setState(() => _focus = v),
        onShowHoverHighlight: widget.onHover,
        mouseCursor: _enabled ? (widget.cursor ?? SystemMouseCursors.click) : MouseCursor.defer,
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
            widget.onTap?.call();
            return null;
          }),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: _enabled ? (_) => setState(() => _down = true) : null,
          onTapUp: _enabled ? (_) => setState(() => _down = false) : null,
          onTapCancel: _enabled ? () => setState(() => _down = false) : null,
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          excludeFromSemantics: true,
          child: child,
        ),
      ),
    );
  }
}

/// `PrimaryPill`: tx on bg, 44-52 tall.
class PrimaryPill extends StatelessWidget {
  const PrimaryPill({
    super.key,
    required this.label,
    this.onTap,
    this.height = 44,
    this.background,
    this.foreground,
    this.padding = 16,
    this.expand = false,
    this.loading = false,
  });
  final String label;
  final VoidCallback? onTap;
  final double height, padding;
  final Color? background, foreground;
  final bool expand, loading;

  @override
  Widget build(BuildContext context) {
    final c = PlannerColors.of(context);
    final enabled = onTap != null;
    return Pressable(
      onTap: onTap,
      label: label,
      excludeChildSemantics: true,
      child: AnimatedOpacity(
        duration: PlannerMotion.of(context, PlannerMotion.snap),
        opacity: enabled ? 1 : 0.4,
        child: Container(
          height: height,
          width: expand ? double.infinity : null,
          padding: EdgeInsets.symmetric(horizontal: padding),
          decoration: BoxDecoration(
            color: background ?? c.tx,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Stack(alignment: Alignment.center, children: [
            const SizedBox(height: double.infinity),
            Text(label,
                maxLines: 1,
                style: PlannerType.ui(height >= 48 ? 14 : 12.5,
                    color: foreground ?? c.bg)),
            if (loading)
              Positioned(
                  left: 0, right: 0, bottom: 6, child: LoadingSweep(color: foreground ?? c.bg)),
          ]),
        ),
      ),
    );
  }
}

/// `SecondaryPill`: 1px ln outline.
class SecondaryPill extends StatelessWidget {
  const SecondaryPill({
    super.key,
    required this.label,
    this.onTap,
    this.height = 44,
    this.padding = 16,
    this.expand = false,
    this.color,
  });
  final String label;
  final VoidCallback? onTap;
  final double height, padding;
  final bool expand;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = PlannerColors.of(context);
    return Pressable(
      onTap: onTap,
      label: label,
      excludeChildSemantics: true,
      child: Opacity(
        opacity: onTap == null ? 0.4 : 1,
        child: Container(
          height: height,
          width: expand ? double.infinity : null,
          padding: EdgeInsets.symmetric(horizontal: padding),
          alignment: expand ? Alignment.center : null,
          decoration: BoxDecoration(
            border: Border.all(color: c.ln),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Center(
            widthFactor: 1,
            child: Text(label,
              maxLines: 1,
                style: PlannerType.ui(height >= 48 ? 14 : 12.5, color: color ?? c.tx)),
          ),
        ),
      ),
    );
  }
}

/// Text-only pill ("Keep anyway", "Later").
class TextPill extends StatelessWidget {
  const TextPill({super.key, required this.label, this.onTap, this.height = 44, this.color});
  final String label;
  final VoidCallback? onTap;
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = PlannerColors.of(context);
    return Pressable(
      onTap: onTap,
      label: label,
      excludeChildSemantics: true,
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Center(
            widthFactor: 1, child: Text(label, style: PlannerType.ui(12.5, color: color ?? c.t2))),
      ),
    );
  }
}

/// `IconButton` (44).
class PlannerIconButton extends StatelessWidget {
  const PlannerIconButton({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.size = 22,
    this.color,
  });
  final PIcon icon;
  final String label;
  final VoidCallback? onTap;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = PlannerColors.of(context);
    return Pressable(
      onTap: onTap,
      label: label,
      pressedScale: 0.92,
      excludeChildSemantics: true,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Center(child: PlannerIcon(icon, size: size, color: color ?? c.tx)),
      ),
    );
  }
}

/// `SegmentedControl`: a pill track with a thumb that springs between
/// options (Spring 460). Exposes pressed state and arrow-key traversal.
class SegmentedPill<T> extends StatelessWidget {
  const SegmentedPill({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.width,
    this.height = 36,
    this.outlined = false,
    this.fontSize = 13,
    this.bumpIndex,
    this.label,
  });

  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;
  final double? width;
  final double height;

  /// Outlined track (Strip/Dial) vs s1 track (Today/Tomorrow).
  final bool outlined;
  final double fontSize;

  /// Index whose label bumps (incoming move to Tomorrow).
  final int? bumpIndex;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = PlannerColors.of(context);
    final idx = options.indexWhere((o) => o.$1 == value);
    final n = options.length;
    return Semantics(
      label: label,
      container: true,
      child: Container(
        width: width,
        height: height,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: outlined ? null : c.s1,
          border: outlined ? Border.all(color: c.ln) : null,
          borderRadius: BorderRadius.circular(999),
        ),
        child: LayoutBuilder(builder: (context, box) {
          final w = box.maxWidth / n;
          return Stack(children: [
            AnimatedPositioned(
              duration: PlannerMotion.ms(context, 460),
              curve: PlannerMotion.springCurve,
              left: w * (idx < 0 ? 0 : idx),
              top: 0,
              bottom: 0,
              width: w,
              child: Container(
                decoration: BoxDecoration(
                  color: outlined ? c.s1 : c.s2,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            Row(children: [
              for (var i = 0; i < n; i++)
                Expanded(
                  child: Pressable(
                    onTap: () => onChanged(options[i].$1),
                    label: options[i].$2,
                    selected: i == idx,
                    excludeChildSemantics: true,
                    pressedScale: 1,
                    child: Center(
                      child: Bump(
                        on: bumpIndex == i,
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 200),
                          style: PlannerType.ui(fontSize, color: i == idx ? c.tx : c.t3),
                          child: Text(options[i].$2, maxLines: 1),
                        ),
                      ),
                    ),
                  ),
                ),
            ]),
          ]);
        }),
      ),
    );
  }
}

/// Scale bump for incoming moves (Plan tab 1.12, Tomorrow 1.08).
class Bump extends StatelessWidget {
  const Bump({super.key, required this.on, required this.child, this.scale = 1.08});
  final bool on;
  final Widget child;
  final double scale;
  @override
  Widget build(BuildContext context) => AnimatedScale(
        scale: on ? scale : 1,
        duration: PlannerMotion.ms(context, 420),
        curve: const Cubic(0.34, 1.6, 0.55, 1),
        child: child,
      );
}


/// `PlannerSwitch` (40 × 24, thumb 18, Spring 420, role=switch).
class PlannerSwitch extends StatelessWidget {
  const PlannerSwitch({super.key, required this.value, required this.onChanged, this.label});
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = PlannerColors.of(context);
    return Pressable(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      label: label,
      toggled: value,
      excludeChildSemantics: true,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: AnimatedContainer(
            duration: PlannerMotion.ms(context, 240),
            width: 40,
            height: 24,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: value ? c.tx : c.s2,
              borderRadius: BorderRadius.circular(999),
            ),
            child: AnimatedAlign(
              duration: PlannerMotion.ms(context, 420),
              curve: PlannerMotion.springCurve,
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: AnimatedContainer(
                duration: PlannerMotion.ms(context, 240),
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: value ? c.bg : c.t2,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `ChoiceChip` (36): selected = tx fill.
class PlannerChip extends StatelessWidget {
  const PlannerChip({
    super.key,
    required this.label,
    required this.selected,
    this.onTap,
    this.leading,
    this.height = 36,
    this.filledWhenIdle = false,
    this.mono = false,
  });
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final Widget? leading;
  final double height;

  /// The label is a time (Geist Mono).
  final bool mono;

  /// s1 background when idle (onboarding style) instead of an outline.
  final bool filledWhenIdle;

  @override
  Widget build(BuildContext context) {
    final c = PlannerColors.of(context);
    return Pressable(
      onTap: onTap,
      label: label,
      selected: selected,
      excludeChildSemantics: true,
      child: SizedBox(
        height: 44,
        child: Center(
          widthFactor: 1,
          child: AnimatedContainer(
            duration: PlannerMotion.of(context, PlannerMotion.snap),
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: selected ? c.tx : (filledWhenIdle ? c.s1 : null),
              border: Border.all(
                  color: selected ? c.tx : (filledWhenIdle ? c.s1 : c.ln)),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (leading != null) ...[leading!, const SizedBox(width: 8)],
              Text(label,
                  style: mono
                      ? PlannerType.time(size: 12, weight: 500, color: selected ? c.bg : c.t2)
                      : PlannerType.ui(13, color: selected ? c.bg : c.t2)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Loading: a 2px bar sweeps inside the control (no spinners).
class LoadingSweep extends StatefulWidget {
  const LoadingSweep({super.key, required this.color, this.height = 2});
  final Color color;
  final double height;
  @override
  State<LoadingSweep> createState() => _LoadingSweepState();
}

class _LoadingSweepState extends State<LoadingSweep> with SingleTickerProviderStateMixin {
  late final _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat();

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(builder: (context, box) {
        return ClipRect(
          child: AnimatedBuilder(
            animation: _a,
            builder: (context, _) => Stack(children: [
              Positioned(
                left: -box.maxWidth * 0.4 + _a.value * box.maxWidth * 1.4,
                width: box.maxWidth * 0.4,
                top: 0,
                bottom: 0,
                child: ColoredBox(color: widget.color.withValues(alpha: 0.7)),
              ),
            ]),
          ),
        );
      }),
    );
  }
}

/// Category square (8×8 by default, radius 2).
class CatSquare extends StatelessWidget {
  const CatSquare(this.color, {super.key, this.size = 8});
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
      );
}

/// Calm s1 panel row (over-capacity, missed prompt). The text sits beside
/// the actions, or above them when it would get narrower than 140px (large
/// text scale): rows grow rather than truncate.
class CalmRow extends StatelessWidget {
  const CalmRow({super.key, required this.child, required this.actions});
  final Widget child;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) {
    final c = PlannerColors.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: BoxDecoration(color: c.s1, borderRadius: BorderRadius.circular(12)),
      child: _SideOrBelow(
        minMain: 140,
        gap: 6,
        main: child,
        side: Row(mainAxisSize: MainAxisSize.min, children: actions),
      ),
    );
  }
}

/// Lays [side] to the right of [main] when [main] keeps at least [minMain]
/// width, otherwise below it (right-aligned).
class _SideOrBelow extends MultiChildRenderObjectWidget {
  _SideOrBelow({required Widget main, required Widget side, required this.minMain, required this.gap})
      : super(children: [main, side]);
  final double minMain, gap;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderSideOrBelow(minMain, gap);

  @override
  void updateRenderObject(BuildContext context, _RenderSideOrBelow r) => r
    ..minMain = minMain
    ..gap = gap;
}

class _SideParent extends ContainerBoxParentData<RenderBox> {}

class _RenderSideOrBelow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _SideParent>,
        RenderBoxContainerDefaultsMixin<RenderBox, _SideParent> {
  _RenderSideOrBelow(this._minMain, this._gap);
  double _minMain, _gap;
  set minMain(double v) {
    if (v == _minMain) return;
    _minMain = v;
    markNeedsLayout();
  }

  set gap(double v) {
    if (v == _gap) return;
    _gap = v;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _SideParent) child.parentData = _SideParent();
  }

  @override
  void performLayout() {
    final main = firstChild!, side = childAfter(main)!;
    final w = constraints.maxWidth;
    side.layout(BoxConstraints(maxWidth: w), parentUsesSize: true);
    final room = w - side.size.width - _gap;
    final mp = main.parentData! as _SideParent, sp = side.parentData! as _SideParent;
    if (room >= _minMain) {
      main.layout(BoxConstraints(minWidth: room, maxWidth: room), parentUsesSize: true);
      final h = main.size.height > side.size.height ? main.size.height : side.size.height;
      mp.offset = Offset(0, (h - main.size.height) / 2);
      sp.offset = Offset(w - side.size.width, (h - side.size.height) / 2);
      size = constraints.constrain(Size(w, h));
    } else {
      main.layout(BoxConstraints(minWidth: w, maxWidth: w), parentUsesSize: true);
      mp.offset = Offset.zero;
      sp.offset = Offset(w - side.size.width, main.size.height + _gap);
      size = constraints.constrain(Size(w, main.size.height + _gap + side.size.height));
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);
}
