import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/plan/plan_page.dart';
import '../features/progress/progress_page.dart';
import '../features/settings/settings_page.dart';
import '../features/today/today_page.dart';
import 'shell.dart';
import 'state/ui_state.dart';

String tabPath(AppTab t) => switch (t) {
      AppTab.today => '/today',
      AppTab.plan => '/plan',
      AppTab.progress => '/progress',
      AppTab.settings => '/settings',
    };

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/today',
    routes: [
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
