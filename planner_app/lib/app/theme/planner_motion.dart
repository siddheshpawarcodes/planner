import 'package:flutter/widgets.dart';

/// Carries the user's Motion setting (System / Reduced / Full) down the tree
/// so [PlannerMotion.of] can combine it with the platform flag.
class MotionPrefs extends InheritedWidget {
  const MotionPrefs({super.key, required this.reduced, required super.child});

  /// null = follow the system, true = Reduced, false = Full.
  final bool? reduced;

  static bool? settingOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MotionPrefs>()?.reduced;

  @override
  bool updateShouldNotify(MotionPrefs oldWidget) => reduced != oldWidget.reduced;
}

/// Motion tokens (README 3.5). Four tokens and nothing else.
///
/// Reduced motion (`MediaQuery.disableAnimations` or Settings, Motion,
/// Reduced): durations × 0.01, orb frozen, no ripples, pulse or wobble, blur
/// off, voice script at 0.35×, placement appears in place. State always
/// commits before any animation; no feature waits for one to finish.
abstract final class PlannerMotion {
  /// Press, toggle, check stroke, drag pickup.
  static const snap = Duration(milliseconds: 160);

  /// Screens, tabs, days, sheets, colour.
  static const settle = Duration(milliseconds: 420);

  /// Placement, drag release, reflow, counters, capacity.
  static const spring = Duration(milliseconds: 640);

  /// Ambient only: orb breath, now pulse.
  static const drift = Duration(milliseconds: 2600);

  static const snapCurve = Cubic(0.3, 0, 0.2, 1);
  static const settleCurve = Cubic(0.2, 0.8, 0.2, 1);
  static const springCurve = Cubic(0.34, 1.35, 0.55, 1);
  static const driftCurve = Curves.easeInOut;

  /// The orb's rise from the nav: 760ms Cubic(.34, 1.22, .5, 1).
  static const wakeCurve = Cubic(0.34, 1.22, 0.5, 1);

  /// Softer spring used by the board (Cubic(.34, 1.3, .55, 1) in CSS).
  static const boardCurve = Cubic(0.34, 1.3, 0.55, 1);

  /// Swipe return (Cubic(.34, 1.45, .55, 1)).
  static const swipeReturnCurve = Cubic(0.34, 1.45, 0.55, 1);

  static const springDescription =
      SpringDescription(mass: 1, stiffness: 260, damping: 20);

  /// True when motion should be reduced for this subtree.
  static bool reduced(BuildContext c) {
    final setting = MotionPrefs.settingOf(c);
    if (setting != null) return setting;
    return MediaQuery.maybeDisableAnimationsOf(c) ?? false;
  }

  /// Scales [d] by 0.01 under reduced motion.
  static Duration of(BuildContext c, Duration d) =>
      reduced(c) ? d * 0.01 : d;

  /// Millisecond helper: `PlannerMotion.ms(context, 620)`.
  static Duration ms(BuildContext c, int ms) =>
      of(c, Duration(milliseconds: ms));

  /// Script multiplier for timed sequences (prototype `M()`):
  /// 1 in full motion, [reducedFactor] when reduced.
  static double factor(BuildContext c, {double reducedFactor = 0.05}) =>
      reduced(c) ? reducedFactor : 1;
}
