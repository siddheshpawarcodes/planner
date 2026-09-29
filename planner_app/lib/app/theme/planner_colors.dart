import 'package:flutter/material.dart';

/// Neutral grounds (README 3.1). Depth comes only from bg → s1 → s2; there
/// are no drop shadows inside the app.
@immutable
class PlannerColors extends ThemeExtension<PlannerColors> {
  const PlannerColors({
    required this.bg,
    required this.s1,
    required this.s2,
    required this.ln,
    required this.tx,
    required this.t2,
    required this.t3,
    required this.veil,
    required this.scrim,
    required this.isDark,
  });

  /// Page ground.
  final Color bg;

  /// Sheets, panels, tracks.
  final Color s1;

  /// Thumbs, raised chips, note strip.
  final Color s2;

  /// Hairlines, dashed open time.
  final Color ln;

  /// Text, now-line, primary buttons.
  final Color tx;

  /// Secondary text.
  final Color t2;

  /// Meta and times (≥ 4.5:1 on bg in both themes).
  final Color t3;

  /// Voice overlay.
  final Color veil;

  /// Behind sheets.
  final Color scrim;
  final bool isDark;

  static const dark = PlannerColors(
    bg: Color(0xFF0F1012),
    s1: Color(0xFF1A1B1E),
    s2: Color(0xFF25272B),
    ln: Color(0xFF2E3035),
    tx: Color(0xFFF2F2EF),
    t2: Color(0xFFA9ABB0),
    t3: Color(0xFF80838A),
    veil: Color(0xDB0F1012), // rgba(15,16,18,.86)
    scrim: Color(0x85000000), // rgba(0,0,0,.52)
    isDark: true,
  );

  static const light = PlannerColors(
    bg: Color(0xFFF4F3EF),
    s1: Color(0xFFE8E7E2),
    s2: Color(0xFFDCDAD3),
    ln: Color(0xFFD3D1CA),
    tx: Color(0xFF121212),
    t2: Color(0xFF4D4D4A),
    t3: Color(0xFF686863),
    veil: Color(0xE0F4F3EF), // rgba(244,243,239,.88)
    scrim: Color(0x4D121212), // rgba(18,18,18,.30)
    isDark: false,
  );

  static PlannerColors of(BuildContext context) =>
      Theme.of(context).extension<PlannerColors>() ?? dark;

  /// Mixes [c] into bg by [t] (prototype `mixHex(bg, c, t)`).
  Color mix(Color c, double t) => Color.lerp(bg, c, t)!;

  @override
  PlannerColors copyWith({
    Color? bg,
    Color? s1,
    Color? s2,
    Color? ln,
    Color? tx,
    Color? t2,
    Color? t3,
    Color? veil,
    Color? scrim,
    bool? isDark,
  }) =>
      PlannerColors(
        bg: bg ?? this.bg,
        s1: s1 ?? this.s1,
        s2: s2 ?? this.s2,
        ln: ln ?? this.ln,
        tx: tx ?? this.tx,
        t2: t2 ?? this.t2,
        t3: t3 ?? this.t3,
        veil: veil ?? this.veil,
        scrim: scrim ?? this.scrim,
        isDark: isDark ?? this.isDark,
      );

  @override
  PlannerColors lerp(covariant PlannerColors? other, double t) {
    if (other == null) return this;
    return PlannerColors(
      bg: Color.lerp(bg, other.bg, t)!,
      s1: Color.lerp(s1, other.s1, t)!,
      s2: Color.lerp(s2, other.s2, t)!,
      ln: Color.lerp(ln, other.ln, t)!,
      tx: Color.lerp(tx, other.tx, t)!,
      t2: Color.lerp(t2, other.t2, t)!,
      t3: Color.lerp(t3, other.t3, t)!,
      veil: Color.lerp(veil, other.veil, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
      isDark: t < 0.5 ? isDark : other.isDark,
    );
  }
}
