import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planner_app/app/theme/planner_theme.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  test('every category ink passes AA on its colour', () {
    for (final c in Category.values) {
      expect(contrast(c.ink, c.color), greaterThanOrEqualTo(4.5),
          reason: '${c.label} ink');
    }
  });

  test('t2 and t3 are at least 4.5:1 on bg in both themes', () {
    for (final t in [PlannerColors.dark, PlannerColors.light]) {
      expect(contrast(t.t3, t.bg), greaterThanOrEqualTo(4.5));
      expect(contrast(t.t2, t.bg), greaterThanOrEqualTo(4.5));
      expect(contrast(t.tx, t.bg), greaterThanOrEqualTo(12));
    }
  });

  test('tints mix 20% dark, 16% light; bands 26% and 20%', () {
    const d = PlannerColors.dark, l = PlannerColors.light;
    expect(Category.study.tint(d), Color.lerp(d.bg, Category.study.color, 0.2));
    expect(Category.study.tint(l), Color.lerp(l.bg, Category.study.color, 0.16));
    expect(Category.rest.band(d), Color.lerp(d.bg, Category.rest.color, 0.26));
    expect(Category.rest.band(l), Color.lerp(l.bg, Category.rest.color, 0.20));
  });

  testWidgets('reduced motion scales durations by 0.01', (tester) async {
    late Duration full, reduced, fromSetting;
    await tester.pumpWidget(Builder(builder: (c) {
      full = PlannerMotion.of(c, PlannerMotion.spring);
      return const SizedBox();
    }));
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: Builder(builder: (c) {
        reduced = PlannerMotion.of(c, PlannerMotion.spring);
        return const SizedBox();
      }),
    ));
    await tester.pumpWidget(MotionPrefs(
      reduced: true,
      child: Builder(builder: (c) {
        fromSetting = PlannerMotion.of(c, PlannerMotion.settle);
        return const SizedBox();
      }),
    ));
    expect(full, const Duration(milliseconds: 640));
    expect(reduced, const Duration(microseconds: 6400));
    expect(fromSetting, const Duration(microseconds: 4200));
  });

  test('theme carries the extension and lerps it', () {
    final t = plannerTheme(PlannerColors.dark);
    expect(t.extension<PlannerColors>(), PlannerColors.dark);
    final mid = PlannerColors.dark.lerp(PlannerColors.light, 1);
    expect(mid.bg, PlannerColors.light.bg);
    expect(mid.isDark, isFalse);
  });
}
