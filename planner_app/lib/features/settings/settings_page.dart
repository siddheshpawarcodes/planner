import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/dev/dev_panel.dart';
import '../../app/theme/planner_theme.dart';

/// Settings (README 6.10). Built in milestone 10; debug builds carry the
/// developer panel meanwhile.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = PlannerColors.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
      children: [
        Text('Settings', style: PlannerType.screenTitle(color: c.tx)),
        if (kDebugMode) const DevPanel(),
      ],
    );
  }
}
