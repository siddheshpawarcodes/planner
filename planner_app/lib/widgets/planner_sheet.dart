import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/state/ui_state.dart';
import '../app/theme/planner_theme.dart';
import '../features/tasks/decision_sheet.dart';
import '../features/tasks/detail_sheet.dart';
import '../features/tasks/task_sheet.dart';
import 'controls.dart';
import 'icons.dart';

/// Hosts the one open sheet (README 7.7 `PlannerSheet`): 24 top radius,
/// 36 × 4 handle, Settle 460 up from 104%, scrim behind, drag down to close.
/// Keeps the last sheet mounted while it slides out.
class SheetHost extends ConsumerStatefulWidget {
  const SheetHost({super.key});
  @override
  ConsumerState<SheetHost> createState() => _SheetHostState();
}

class _SheetHostState extends ConsumerState<SheetHost> with SingleTickerProviderStateMixin {
  late final AnimationController _a;
  SheetState? _shown;
  double _drag = 0;

  @override
  void initState() {
    super.initState();
    _a = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  void _sync(SheetState? next) {
    _a.duration = PlannerMotion.ms(context, 460);
    if (next != null) {
      setState(() {
        _shown = next;
        _drag = 0;
      });
      _a.forward();
    } else {
      _a.duration = PlannerMotion.ms(context, 420);
      _a.reverse().whenComplete(() {
        if (mounted && ref.read(sheetProvider) == null) setState(() => _shown = null);
      });
    }
  }

  void _close() => ref.read(sheetProvider.notifier).close();

  @override
  Widget build(BuildContext context) {
    ref.listen(sheetProvider, (prev, next) => _sync(next));
    final c = PlannerColors.of(context);
    final mq = MediaQuery.of(context);
    final shown = _shown;
    final open = ref.watch(sheetProvider) != null;
    if (shown == null) return const SizedBox.shrink();
    return PopScope(
      canPop: !open,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Stack(children: [
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !open,
            child: GestureDetector(
              onTap: _close,
              child: FadeTransition(
                opacity: CurvedAnimation(parent: _a, curve: Curves.easeOut),
                child: ColoredBox(color: c.scrim),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: AnimatedBuilder(
            animation: _a,
            builder: (context, child) {
              final v = PlannerMotion.settleCurve.transform(_a.value);
              return FractionalTranslation(
                translation: Offset(0, (1 - v) * 1.04),
                child: Transform.translate(offset: Offset(0, _drag), child: child),
              );
            },
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: (mq.size.height - mq.padding.top - 12).clamp(0, 800)),
              child: Semantics(
                scopesRoute: true,
                namesRoute: true,
                explicitChildNodes: true,
                label: switch (shown.kind) {
                  SheetKind.detail => 'Task details',
                  SheetKind.decision => 'Decide',
                  SheetKind.create => 'New task',
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: c.s1,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onVerticalDragUpdate: (d) =>
                          setState(() => _drag = (_drag + d.delta.dy).clamp(0, 600)),
                      onVerticalDragEnd: (d) {
                        if (_drag > 90 || d.velocity.pixelsPerSecond.dy > 700) {
                          _close();
                        } else {
                          setState(() => _drag = 0);
                        }
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.only(top: 8, bottom: 10),
                        alignment: Alignment.center,
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration:
                              BoxDecoration(color: c.ln, borderRadius: BorderRadius.circular(2)),
                        ),
                      ),
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(20, 0, 20, 30 + mq.padding.bottom),
                        child: KeyedSubtree(
                          key: ValueKey(shown),
                          child: switch (shown.kind) {
                            SheetKind.detail => DetailSheet(taskId: shown.taskId!),
                            SheetKind.decision =>
                              DecisionSheet(taskId: shown.taskId!, reschedule: shown.reschedule),
                            SheetKind.create => TaskSheet(draft: shown.draft ?? const TaskDraft()),
                          },
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Close (×) button used in sheet headers.
class SheetClose extends ConsumerWidget {
  const SheetClose({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Transform.translate(
        offset: const Offset(10, 0),
        child: PlannerIconButton(
          icon: PIcon.close,
          label: 'Close',
          size: 20,
          color: PlannerColors.of(context).t2,
          onTap: () => ref.read(sheetProvider.notifier).close(),
        ),
      );
}

/// A full-width row inside sheets: label left, value right, hairline above.
class SheetRow extends StatelessWidget {
  const SheetRow({
    super.key,
    required this.label,
    this.value,
    this.trailing,
    this.onTap,
    this.enabled = true,
    this.color,
    this.valueColor,
    this.minHeight = 56,
    this.mono = true,
  });
  final String label;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled, mono;
  final Color? color, valueColor;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final c = PlannerColors.of(context);
    final row = Container(
      constraints: BoxConstraints(minHeight: minHeight),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: c.ln))),
      child: Row(children: [
        Expanded(
          child: Text(label,
              style: PlannerType.ui(15, color: color ?? (enabled ? c.tx : c.t3))),
        ),
        if (value != null)
          Text(value!,
              style: mono
                  ? PlannerType.time(size: 13, color: valueColor ?? (enabled ? c.t2 : c.t3))
                  : PlannerType.ui(12, weight: 400, color: valueColor ?? c.t3)),
        ?trailing,
      ]),
    );
    if (onTap == null) return row;
    return Pressable(
      onTap: enabled ? onTap : null,
      label: value == null ? label : '$label, $value',
      radius: 0,
      pressedScale: 0.99,
      excludeChildSemantics: true,
      child: row,
    );
  }
}
