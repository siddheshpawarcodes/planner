import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/settings.dart';
import 'router.dart';
import 'state/derived.dart';
import 'state/ui_state.dart';
import 'theme/planner_theme.dart';

class PlannerApp extends ConsumerWidget {
  const PlannerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return MaterialApp.router(
      title: 'Planner',
      debugShowCheckedModeBanner: false,
      theme: plannerTheme(PlannerColors.light),
      darkTheme: plannerTheme(PlannerColors.dark),
      themeMode: switch (settings.theme) {
        ThemeChoice.system => ThemeMode.system,
        ThemeChoice.dark => ThemeMode.dark,
        ThemeChoice.light => ThemeMode.light,
      },
      themeAnimationDuration: themeAnimationDuration,
      themeAnimationCurve: themeAnimationCurve,
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) => _MotionScope(child: child!),
    );
  }
}

/// Publishes the Motion setting to [PlannerMotion.of] and keeps the
/// platform's reduce-motion flag in [platformReducedMotionProvider]. Text
/// scale is capped at 1.3× (rows grow rather than truncate).
class _MotionScope extends ConsumerWidget {
  const _MotionScope({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final platform = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => ref.read(platformReducedMotionProvider.notifier).set(platform));
    final setting = ref.watch(settingsProvider.select((s) => s.reducedMotion));
    final mq = MediaQuery.of(context);
    return MediaQuery(
      data: mq.copyWith(textScaler: mq.textScaler.clamp(maxScaleFactor: 1.3)),
      child: MotionPrefs(reduced: setting ?? platform, child: child),
    );
  }
}
