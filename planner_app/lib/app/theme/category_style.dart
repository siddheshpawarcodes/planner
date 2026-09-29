import 'package:flutter/material.dart';

import '../../domain/category.dart';
import 'planner_colors.dart';

export '../../domain/category.dart';

/// Category colours (README 3.2). A transit map, not a rainbow: full colour
/// only for current and next; everything else is a tint.
extension CategoryStyle on Category {
  Color get color => Color(const [
        0xFF2450E6, // Study
        0xFF00875A, // Build
        0xFFD9331A, // Body
        0xFFC92A76, // People
        0xFFF5B800, // Self
        0xFF5A6B7D, // Work
        0xFF8C6A40, // Rest (darkened from #A07A4C so white ink passes AA)
      ][index]);

  /// Text on the full colour. All inks pass AA.
  Color get ink =>
      this == Category.self ? const Color(0xFF1A1404) : const Color(0xFFFFFFFF);

  /// Quiet tint: 20% of the colour mixed into bg in dark, 16% in light.
  Color tint(PlannerColors c) => c.mix(color, c.isDark ? 0.20 : 0.16);

  /// Commitment band: 26% dark, 20% light.
  Color band(PlannerColors c) => c.mix(color, c.isDark ? 0.26 : 0.20);

  /// Arbitrary mix into bg.
  Color tintAt(PlannerColors c, double t) => c.mix(color, t);
}
