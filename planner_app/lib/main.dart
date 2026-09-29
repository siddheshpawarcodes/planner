import 'package:flutter/material.dart';

import 'app/dev/foundations_page.dart';
import 'app/theme/planner_theme.dart';

void main() => runApp(const PlannerApp());

class PlannerApp extends StatelessWidget {
  const PlannerApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Planner',
        debugShowCheckedModeBanner: false,
        theme: plannerTheme(PlannerColors.light),
        darkTheme: plannerTheme(PlannerColors.dark),
        themeAnimationDuration: themeAnimationDuration,
        themeAnimationCurve: themeAnimationCurve,
        home: const FoundationsPage(),
      );
}
