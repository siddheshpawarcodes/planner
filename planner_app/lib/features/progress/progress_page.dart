import 'package:flutter/material.dart';

import '../../app/theme/planner_theme.dart';

/// Progress (README 6.8). Built in milestone 9.
class ProgressPage extends StatelessWidget {
  const ProgressPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = PlannerColors.of(context);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Text('This week', style: PlannerType.screenTitle(color: c.tx)),
    );
  }
}
