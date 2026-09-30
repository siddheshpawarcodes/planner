import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/dev/dev_panel.dart';
import '../../app/state/actions.dart';
import '../../app/state/derived.dart';
import '../../app/theme/planner_theme.dart';
import '../../domain/time.dart';
import '../../widgets/controls.dart';
import '../../widgets/icons.dart';

/// Settings (README 6.10). The Routine section is live; the other sections
/// arrive in milestone 10. Debug builds carry the developer panel.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = PlannerColors.of(context);
    final r = ref.watch(routineProvider);
    final rows = [
      ('Wake', fmt(r.wake)),
      ('Work', r.noFixedWork ? 'No fixed hours' : '${fmt(r.workStart)} → ${fmt(r.workEnd)}'),
      ('Sleep', fmt(r.sleep)),
      ('Commitments', '${r.commitments.where((x) => x.on).length} recurring'),
    ];
    final line = BorderSide(color: c.ln);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
      children: [
        SizedBox(
          height: 44,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Semantics(header: true, child: Text('Settings', style: PlannerType.screenTitle(color: c.tx))),
          ),
        ),
        const SizedBox(height: 26),
        Semantics(
          header: true,
          child: Text('Routine', style: PlannerType.bricolage600(15, color: c.tx)),
        ),
        const SizedBox(height: 6),
        for (final (k, v) in rows)
          Semantics(
            label: '$k, ${v.replaceAll('→', 'to')}',
            excludeSemantics: true,
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              decoration: BoxDecoration(border: Border(top: line)),
              child: Row(children: [
                Expanded(child: Text(k, style: PlannerType.body(size: 14, color: c.t2))),
                Text(v, style: PlannerType.time(size: 13, color: c.tx)),
              ]),
            ),
          ),
        Pressable(
          onTap: ref.read(actionsProvider).editRoutine,
          label: 'Edit routine',
          radius: 4,
          pressedScale: 0.99,
          excludeChildSemantics: true,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            decoration: BoxDecoration(border: Border(top: line)),
            child: Row(children: [
              Expanded(child: Text('Edit routine', style: PlannerType.ui(14, color: c.tx))),
              PlannerIcon(PIcon.chev, size: 16, color: c.t3, stroke: 1.6),
            ]),
          ),
        ),
        if (kDebugMode) ...[const SizedBox(height: 10), const DevPanel()],
      ],
    );
  }
}
