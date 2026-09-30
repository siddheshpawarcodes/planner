import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/onboarding/onboarding_page.dart';
import '../features/plan/plan_page.dart';
import '../features/progress/review_page.dart';
import '../features/progress/progress_page.dart';
import '../features/settings/settings_page.dart';
import '../features/today/today_page.dart';
import 'shell.dart';
import 'state/store.dart';
import 'state/ui_state.dart';
import 'theme/planner_theme.dart';

String tabPath(AppTab t) => switch (t) {
      AppTab.today => '/today',
      AppTab.plan => '/plan',
      AppTab.progress => '/progress',
      AppTab.settings => '/settings',
    };

/// Onboarding sits outside the shell. First launch opens it; Settings ›
/// Edit routine pushes it prefilled (`/onboarding?edit=1`).
const onboardingPath = '/onboarding';

/// The weekly review: a full-screen route over the shell.
const reviewPath = '/review';

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: ref.read(plannerStoreProvider).onboarded ? '/today' : onboardingPath,
    routes: [
      GoRoute(
        path: onboardingPath,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: OnboardingPage(edit: state.uri.queryParameters['edit'] == '1'),
          transitionDuration: const Duration(milliseconds: 420),
          // Leaving, onboarding runs its own scale-and-blur exit first.
          reverseTransitionDuration: Duration.zero,
          transitionsBuilder: (context, a, _, child) => PlannerMotion.reduced(context)
              ? child
              : FadeTransition(
                  opacity: CurvedAnimation(parent: a, curve: PlannerMotion.settleCurve), child: child),
        ),
      ),
      GoRoute(
        path: reviewPath,
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const ReviewPage(),
          transitionDuration: const Duration(milliseconds: 520),
          reverseTransitionDuration: const Duration(milliseconds: 420),
          transitionsBuilder: (context, a, _, child) {
            if (PlannerMotion.reduced(context)) return FadeTransition(opacity: a, child: child);
            final s = CurvedAnimation(parent: a, curve: PlannerMotion.settleCurve);
            return FadeTransition(
              opacity: CurvedAnimation(parent: a, curve: const Interval(0, 420 / 520, curve: Curves.ease)),
              child: SlideTransition(
                  position: Tween(begin: const Offset(0, 0.03), end: Offset.zero).animate(s), child: child),
            );
          },
        ),
      ),
      StatefulShellRoute(
        builder: (context, state, shell) => AppShell(shell: shell),
        navigatorContainerBuilder: (context, shell, children) =>
            PaneSwitcher(index: shell.currentIndex, children: children),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/today', builder: (_, _) => const TodayPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/plan', builder: (_, _) => const PlanPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/progress', builder: (_, _) => const ProgressPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/settings', builder: (_, _) => const SettingsPage()),
          ]),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
