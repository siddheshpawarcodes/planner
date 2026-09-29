import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/state/note.dart';
import '../app/theme/planner_theme.dart';
import 'controls.dart';

/// `NoteStrip` (README 7.7): s2, radius 12, rises 12px on a spring, 3.6s or
/// 5.2s with an action. A polite live region: completion, placement and
/// moves are announced here.
class NoteStrip extends ConsumerWidget {
  const NoteStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = PlannerColors.of(context);
    final note = ref.watch(noteProvider);
    final on = note != null;
    return _Remember(
      note: note,
      builder: (shown) => IgnorePointer(
        ignoring: !on,
        child: AnimatedOpacity(
          opacity: on ? 1 : 0,
          duration: PlannerMotion.ms(context, 300),
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: on ? 0 : 12),
            duration: PlannerMotion.ms(context, 520),
            curve: PlannerMotion.springCurve,
            builder: (context, dy, child) => Transform.translate(offset: Offset(0, dy), child: child),
            child: Semantics(
              liveRegion: true,
              container: true,
              child: Container(
                constraints: const BoxConstraints(minHeight: 44),
                padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
                decoration: BoxDecoration(color: c.s2, borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(shown?.text ?? '',
                          style: PlannerType.body(size: 13, color: c.tx).copyWith(height: 1.35)),
                    ),
                  ),
                  if (shown?.actionLabel != null)
                    Pressable(
                      onTap: ref.read(noteProvider.notifier).runAction,
                      label: shown!.actionLabel,
                      excludeChildSemantics: true,
                      child: Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        alignment: Alignment.center,
                        child: Text(shown.actionLabel!,
                            style: PlannerType.ui(13, weight: 600, color: c.tx).copyWith(
                              decoration: TextDecoration.underline,
                              decorationColor: c.tx,
                            )),
                      ),
                    ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Keeps the last note's text while the strip fades out.
class _Remember extends StatefulWidget {
  const _Remember({required this.note, required this.builder});
  final Note? note;
  final Widget Function(Note? shown) builder;
  @override
  State<_Remember> createState() => _RememberState();
}

class _RememberState extends State<_Remember> {
  Note? _last;
  @override
  Widget build(BuildContext context) {
    if (widget.note != null) _last = widget.note;
    return widget.builder(_last);
  }
}
