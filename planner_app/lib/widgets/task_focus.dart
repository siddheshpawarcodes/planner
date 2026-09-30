import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/state/actions.dart';
import '../app/theme/planner_theme.dart';

/// Keyboard focus for a task block (README 8, 9): Enter opens it, Space
/// completes it, Alt ↑↓ moves it 15 minutes, Alt ←→ moves it a day. Focused
/// = a 2px `tx` outline with a 2px offset.
class TaskFocus extends ConsumerStatefulWidget {
  const TaskFocus({super.key, required this.taskId, required this.child, this.radius = 4});
  final String taskId;
  final Widget child;
  final double radius;

  @override
  ConsumerState<TaskFocus> createState() => _TaskFocusState();
}

class _TaskFocusState extends ConsumerState<TaskFocus> {
  bool _focused = false;

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final act = ref.read(actionsProvider);
    final t = act.data.task(widget.taskId);
    if (t == null) return KeyEventResult.ignored;
    final alt = HardwareKeyboard.instance.isAltPressed;
    final k = e.logicalKey;
    if (!alt && (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter)) {
      act.openBlock(t.id);
      return KeyEventResult.handled;
    }
    if (!alt && k == LogicalKeyboardKey.space) {
      act.toggle(t.id);
      return KeyEventResult.handled;
    }
    if (alt && t.isScheduled && !t.done) {
      final (dd, dm) = switch (k) {
        LogicalKeyboardKey.arrowUp => (0, -15),
        LogicalKeyboardKey.arrowDown => (0, 15),
        LogicalKeyboardKey.arrowLeft => (-1, 0),
        LogicalKeyboardKey.arrowRight => (1, 0),
        _ => (0, 0),
      };
      if (dd == 0 && dm == 0) return KeyEventResult.ignored;
      act.dropOnBoard(t.id, t.day! + dd, t.start! + dm);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final c = PlannerColors.of(context);
    return Focus(
      // The block carries its own semantics (label, Complete, Reschedule).
      includeSemantics: false,
      onKeyEvent: _onKey,
      onFocusChange: (v) => setState(() => _focused = v),
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.radius + 2),
          border: _focused
              ? Border.all(color: c.tx, width: 2, strokeAlign: BorderSide.strokeAlignOutside + 1)
              : null,
        ),
        child: widget.child,
      ),
    );
  }
}
