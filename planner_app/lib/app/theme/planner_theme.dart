import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'planner_colors.dart';
import 'planner_motion.dart';
import 'planner_type.dart';

export 'category_style.dart';
export 'planner_colors.dart';
export 'planner_motion.dart';
export 'planner_type.dart';

/// Builds the Material theme around [PlannerColors]. Material is only the
/// host: every Planner widget reads the extension directly.
ThemeData plannerTheme(PlannerColors c) {
  final scheme = ColorScheme(
    brightness: c.isDark ? Brightness.dark : Brightness.light,
    primary: c.tx,
    onPrimary: c.bg,
    secondary: c.t2,
    onSecondary: c.bg,
    error: c.t2, // errors are inline t2 text, never red fills
    onError: c.bg,
    surface: c.bg,
    onSurface: c.tx,
    surfaceContainerLow: c.s1,
    surfaceContainer: c.s1,
    surfaceContainerHigh: c.s2,
    outline: c.ln,
    outlineVariant: c.ln,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.bg,
    canvasColor: c.bg,
    fontFamily: PlannerType.geist,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: c.tx.withValues(alpha: 0.04),
    focusColor: Colors.transparent,
    dividerColor: c.ln,
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: c.tx,
      selectionColor: c.tx.withValues(alpha: 0.22),
      selectionHandleColor: c.tx,
    ),
    textTheme: TextTheme(
      bodyMedium: PlannerType.body(color: c.tx),
      bodySmall: PlannerType.body(size: 13, color: c.t2),
      bodyLarge: PlannerType.body(size: 15, color: c.tx),
      titleLarge: PlannerType.screenTitle(color: c.tx),
      labelLarge: PlannerType.ui(14, color: c.tx),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
    }),
    extensions: [c],
  );
}

/// Theme changes cross-fade over 420ms on the Settle curve.
const themeAnimationDuration = PlannerMotion.settle;
const themeAnimationCurve = PlannerMotion.settleCurve;
