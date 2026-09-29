import 'package:flutter/material.dart';

import '../../app/theme/planner_theme.dart';

/// Plan (README 6.7). Built in milestone 5.
class PlanPage extends StatelessWidget {
  const PlanPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = PlannerColors.of(context);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Text('This week', style: PlannerType.screenTitle(color: c.tx)),
    );
  }
}
