import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/layout.dart';
import '../../app/state/actions.dart';
import '../../app/state/note.dart';
import '../../app/state/ui_state.dart';
import '../../app/theme/planner_theme.dart';
import '../voice/voice_controller.dart';

/// The keyboard model (README 8), listed by "?" and in the Today rail.
const kShortcuts = [
  ('N', 'New task'),
  ('V', 'Talk to Planner'),
  ('T', 'Jump to today'),
  ('← →', 'Previous or next day'),
  ('Enter', 'Open the focused block'),
  ('Space', 'Complete it'),
  ('Alt ↑↓', 'Move 15 minutes'),
  ('Alt ←→', 'Move a day'),
  ('Ctrl Z', 'Undo'),
  ('?', 'Every shortcut'),
];

/// App-wide keys, handled at the shell root so focused blocks and sheets
/// see them first and typing in a field is never hijacked.
class KeyboardHost extends ConsumerStatefulWidget {
  const KeyboardHost({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<KeyboardHost> createState() => _KeyboardHostState();
}

class _KeyboardHostState extends ConsumerState<KeyboardHost> {
  final _node = FocusNode(debugLabel: 'shell keys', skipTraversal: true);

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_regain);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_regain);
    _node.dispose();
    super.dispose();
  }

  /// When focus falls back to the root (a focused block went away), take it
  /// again so shortcuts keep working. Routes above the shell keep theirs.
  void _regain() {
    final p = FocusManager.instance.primaryFocus;
    if (!mounted || (p != null && p != FocusManager.instance.rootScope)) return;
    if (ModalRoute.of(context)?.isCurrent ?? true) _node.requestFocus();
  }

  bool get _typing {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    return ctx.widget is EditableText || ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final hw = HardwareKeyboard.instance;
    final k = e.logicalKey;
    final act = ref.read(actionsProvider);
    final voice = ref.read(voiceControllerProvider);
    final sheet = ref.read(sheetProvider);

    // Esc works even while typing (it closes the sheet); nothing else does.
    if (k == LogicalKeyboardKey.escape) {
      if (voice.open) {
        ref.read(voiceControllerProvider.notifier).veilTap();
        return KeyEventResult.handled;
      }
      if (sheet != null) {
        act.closeSheet();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (_typing) return KeyEventResult.ignored;

    if ((hw.isControlPressed || hw.isMetaPressed) && k == LogicalKeyboardKey.keyZ) {
      final n = ref.read(noteProvider);
      if (n?.action != null && n?.actionLabel == 'Undo') {
        n!.action!();
        ref.read(noteProvider.notifier).dismiss();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (hw.isControlPressed || hw.isMetaPressed || hw.isAltPressed) return KeyEventResult.ignored;
    if (k == LogicalKeyboardKey.keyV) {
      ref.read(voiceControllerProvider.notifier).tapOrb();
      return KeyEventResult.handled;
    }
    if (voice.open || sheet != null) return KeyEventResult.ignored;

    if (e.character == '?' || (k == LogicalKeyboardKey.slash && hw.isShiftPressed)) {
      showShortcuts(context);
      return KeyEventResult.handled;
    }
    switch (k) {
      case LogicalKeyboardKey.keyN:
        act.openCreate();
      case LogicalKeyboardKey.keyT:
        act.goToday();
      case LogicalKeyboardKey.keyP:
        act.goTab(AppTab.plan);
      case LogicalKeyboardKey.keyG:
        act.goTab(AppTab.progress);
      case LogicalKeyboardKey.arrowLeft:
      case LogicalKeyboardKey.arrowRight:
        act.stepDay(k == LogicalKeyboardKey.arrowRight ? 1 : -1, wide: PlannerLayout.of(context).wide);
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) =>
      // No semantics node of its own: it would swallow the labels below it.
      Focus(focusNode: _node, autofocus: true, includeSemantics: false, onKeyEvent: _onKey, child: widget.child);
}

/// "?": every shortcut, in a calm panel (Esc or a tap closes it).
Future<void> showShortcuts(BuildContext context) {
  final c = PlannerColors.of(context);
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close shortcuts',
    barrierColor: c.scrim,
    transitionDuration: PlannerMotion.ms(context, 240),
    transitionBuilder: (context, a, _, child) => FadeTransition(opacity: a, child: child),
    pageBuilder: (context, _, _) => Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 360,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          decoration: BoxDecoration(color: c.s1, borderRadius: BorderRadius.circular(12)),
          child: Semantics(
            scopesRoute: true,
            namesRoute: true,
            explicitChildNodes: true,
            label: 'Keyboard shortcuts',
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Keyboard shortcuts', style: PlannerType.bricolage600(18, color: c.tx)),
              const SizedBox(height: 12),
              const ShortcutLegend(),
            ]),
          ),
        ),
      ),
    ),
  );
}

/// The key legend (the "?" panel and the desktop Today rail).
class ShortcutLegend extends StatelessWidget {
  const ShortcutLegend({super.key, this.dense = false});
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = PlannerColors.of(context);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      for (final (k, t) in kShortcuts)
        Padding(
          padding: EdgeInsets.symmetric(vertical: dense ? 3 : 5),
          child: Row(children: [
            Container(
              constraints: const BoxConstraints(minWidth: 64),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text(k, style: PlannerType.time(size: dense ? 11 : 12, weight: 500, color: c.tx)),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(t, style: PlannerType.ui(dense ? 12 : 13, weight: 400, color: c.t2))),
          ]),
        ),
    ]);
  }
}
