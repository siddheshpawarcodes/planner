import 'package:flutter/painting.dart';

/// Type scale (README 3.3). Rule: if it isn't a time, it isn't mono.
///
/// The fonts are variable, so every style sets the `wght` axis (and the
/// `opsz` axis for Bricolage) explicitly.
abstract final class PlannerType {
  static const bricolage = 'Bricolage';
  static const geist = 'Geist';
  static const mono = 'GeistMono';

  static const _weights = {
    300: FontWeight.w300,
    400: FontWeight.w400,
    500: FontWeight.w500,
    600: FontWeight.w600,
    700: FontWeight.w700,
  };

  static TextStyle _style(
    String family,
    double size,
    int weight, {
    double? height,
    double tracking = 0,
    bool tabular = false,
    bool opsz = false,
    Color? color,
  }) =>
      TextStyle(
        fontFamily: family,
        fontSize: size,
        fontWeight: _weights[weight],
        fontVariations: [
          FontVariation.weight(weight.toDouble()),
          if (opsz) FontVariation.opticalSize(size.clamp(12, 96).toDouble()),
        ],
        height: height,
        letterSpacing: tracking * size,
        fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
        color: color,
        leadingDistribution: TextLeadingDistribution.even,
      );

  /// Bricolage for anything a person wrote or decided.
  static TextStyle bricolage600(double size,
          {double? height, double tracking = 0, Color? color}) =>
      _style(bricolage, size, 600,
          height: height, tracking: tracking, opsz: true, color: color);

  static TextStyle bricolageW(double size, int weight,
          {double? height, double tracking = 0, Color? color}) =>
      _style(bricolage, size, weight,
          height: height, tracking: tracking, opsz: true, color: color);

  /// Bricolage 600 52/1.0, −3% (review).
  static TextStyle display({Color? color}) =>
      bricolage600(52, height: 1.0, tracking: -0.03, color: color);

  /// Bricolage 600 34/1.06, −2% (onboarding).
  static TextStyle question({Color? color}) =>
      bricolage600(34, height: 1.06, tracking: -0.02, color: color);

  /// Bricolage 600 24, −1.5%.
  static TextStyle screenTitle({double size = 24, Color? color}) =>
      bricolage600(size, height: 1.1, tracking: -0.015, color: color);

  /// Bricolage 600 30/1.08.
  static TextStyle sheetTitle({double size = 30, Color? color}) =>
      bricolage600(size, height: 1.08, tracking: -0.015, color: color);

  /// Bricolage 600 15/1.2 (12 in Week blocks).
  static TextStyle taskTitle({double size = 15, Color? color}) =>
      bricolage600(size, height: 1.2, tracking: -0.005, color: color);

  /// Geist 300 64-112/0.9, −5%, tabular.
  static TextStyle numeral(double size, {Color? color}) => _style(
      geist, size, 300,
      height: 0.9, tracking: -0.05, tabular: true, color: color);

  /// Geist 400 13-15/1.45.
  static TextStyle body({double size = 14, int weight = 400, Color? color}) =>
      _style(geist, size, weight, height: 1.45, color: color);

  /// Geist UI text (no fixed leading).
  static TextStyle ui(double size, {int weight = 500, Color? color, double tracking = 0}) =>
      _style(geist, size, weight, tracking: tracking, color: color);

  /// Geist Mono 400-500 11-13, tabular.
  static TextStyle time({double size = 12, int weight = 400, Color? color}) =>
      _style(mono, size, weight, tabular: true, color: color);

  /// Geist Mono 600 9.5-11, +8-16% tracking. NOW, NEXT, MISSED, LISTENING only.
  static TextStyle stateLabel(
          {double size = 10, double tracking = 0.12, int weight = 600, Color? color}) =>
      _style(mono, size, weight, tracking: tracking, tabular: true, color: color);
}
