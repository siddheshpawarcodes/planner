import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/planner_theme.dart';
import '../../domain/intents.dart';
import '../../widgets/controls.dart';
import 'planner_orb.dart';
import 'voice_controller.dart';

/// Vertical layout of the overlay on the 860px reference phone.
const _refHeight = 860.0;

/// `VoiceOverlay` (README 6.3): veil + 18px backdrop blur, the state label
/// at the top, the transcript word by word, then the parsed rows.
class VoiceOverlay extends ConsumerWidget {
  const VoiceOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = PlannerColors.of(context);
    final v = ref.watch(voiceControllerProvider);
    final ctl = ref.read(voiceControllerProvider.notifier);
    final reduced = PlannerMotion.reduced(context);
    final size = MediaQuery.sizeOf(context);
    final k = (size.height / _refHeight).clamp(0.78, 1.2);
    final open = v.open;
    final res = v.res;
    final ms = PlannerMotion.ms;

    final label = switch (v.phase) {
      OrbState.wake => 'HEY PLANNER',
      OrbState.listening => 'LISTENING',
      OrbState.processing => 'UNDERSTANDING',
      OrbState.result => res?.label ?? '',
      OrbState.success => res?.doneLabel ?? 'DONE',
      OrbState.cancelled => 'CANCELLED',
      OrbState.denied => 'MICROPHONE IS OFF',
      OrbState.idle => '',
    };
    final hint = switch (v.phase) {
      OrbState.wake || OrbState.listening =>
        v.live ? 'Your voice shapes the orb. Tap anywhere to cancel.' : 'Tap anywhere to cancel',
      OrbState.processing => 'Tap anywhere to cancel',
      _ when v.waiting && res?.wait == VoiceWait.answer => 'Tap anywhere to close',
      _ => '',
    };

    return IgnorePointer(
      ignoring: !open,
      child: AnimatedOpacity(
        opacity: open ? 1 : 0,
        duration: ms(context, 420),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: ctl.veilTap,
          child: Stack(children: [
            Positioned.fill(
              child: reduced
                  ? ColoredBox(color: c.veil)
                  : BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: ColoredBox(color: c.veil),
                    ),
            ),
            Positioned(
              top: 70 * k,
              left: 0,
              right: 0,
              child: Semantics(
                liveRegion: true,
                child: Text(label,
                    textAlign: TextAlign.center,
                    style: PlannerType.stateLabel(size: 11, tracking: 0.16, weight: 500, color: c.t2)),
              ),
            ),
            // Transcript.
            Positioned(
              top: 492 * k,
              left: 30,
              right: 30,
              child: Semantics(
                label: v.words.join(' '),
                excludeSemantics: true,
                child: Wrap(spacing: 7, runSpacing: 2, children: [
                  for (final (i, w) in v.words.indexed)
                    _Word(
                      key: ValueKey('w$i'),
                      word: w,
                      index: i,
                      shown: v.phase != OrbState.denied,
                      parsed: v.parsed,
                      lifted: v.showRes || v.phase == OrbState.cancelled,
                      isKey: v.keywords.contains(normalizeUtterance(w).replaceAll(',', '')),
                    ),
                ]),
              ),
            ),
            // Parsed rows.
            if (res != null && v.showRes)
              Positioned(
                top: 480 * k,
                left: 30,
                right: 30,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(res.label,
                        style: PlannerType.stateLabel(size: 11, tracking: 0.1, weight: 500, color: c.t2)),
                  ),
                  for (final (i, r) in res.rows.indexed)
                    _Rise(
                      on: i < v.resN,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(border: Border(top: BorderSide(color: c.ln))),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                          CatSquare(r.cat?.color ?? c.t3, size: 10),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(r.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: PlannerType.bricolage600(20, tracking: -0.01, color: c.tx)),
                          ),
                          const SizedBox(width: 12),
                          Text(r.detail, style: PlannerType.time(size: 13, color: c.t2)),
                        ]),
                      ),
                    ),
                  if (res.summary.isNotEmpty)
                    AnimatedOpacity(
                      opacity: v.resN >= res.rows.length ? 1 : 0,
                      duration: const Duration(milliseconds: 300),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(res.summary, style: PlannerType.body(size: 14, color: c.t2)),
                      ),
                    ),
                  if (v.waiting)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Row(children: [
                        PrimaryPill(
                          label: res.yes,
                          height: 48,
                          padding: 20,
                          background: res.wait == VoiceWait.confirm ? Category.body.color : null,
                          foreground: res.wait == VoiceWait.confirm ? Colors.white : null,
                          onTap: ctl.yes,
                        ),
                        if (res.no != null) ...[
                          const SizedBox(width: 8),
                          SecondaryPill(label: res.no!, height: 48, padding: 18, onTap: ctl.no),
                        ],
                      ]),
                    ),
                ]),
              ),
            // Microphone denied.
            if (v.phase == OrbState.denied)
              Positioned(
                top: 470 * k,
                left: 30,
                right: 30,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Planner can’t hear you yet.',
                      style: PlannerType.bricolage600(22, height: 1.2, color: c.tx)),
                  const SizedBox(height: 12),
                  Text(
                      'Voice needs microphone access. Planner only listens while you’re talking to it, never in the background. You can type instead.',
                      style: PlannerType.body(size: 14, color: c.t2).copyWith(height: 1.5)),
                  const SizedBox(height: 16),
                  Row(children: [
                    PrimaryPill(label: 'Allow microphone', height: 48, padding: 18, onTap: ctl.allowMic),
                    const SizedBox(width: 8),
                    SecondaryPill(label: 'Type instead', height: 48, padding: 18, onTap: ctl.typeInstead),
                  ]),
                ]),
              ),
            Positioned(
              bottom: 118 + MediaQuery.paddingOf(context).bottom,
              left: 0,
              right: 0,
              child: AnimatedOpacity(
                opacity: hint.isEmpty ? 0 : 1,
                duration: const Duration(milliseconds: 300),
                child: Text(hint,
                    textAlign: TextAlign.center,
                    style: PlannerType.ui(12, weight: 400, color: c.t3)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// A transcript word: fades and rises 10px while unblurring 6px when it
/// arrives; on understanding, key words go to tx 500 and the rest to t3
/// (22ms stagger); then they lift −18px and blur out (12ms stagger).
class _Word extends StatelessWidget {
  const _Word({
    super.key,
    required this.word,
    required this.index,
    required this.shown,
    required this.parsed,
    required this.lifted,
    required this.isKey,
  });
  final String word;
  final int index;
  final bool shown, parsed, lifted, isKey;

  @override
  Widget build(BuildContext context) {
    final c = PlannerColors.of(context);
    final reduced = PlannerMotion.reduced(context);
    final visible = shown && !lifted;
    final ms = PlannerMotion.ms;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: visible ? 1 : 0),
      duration: ms(context, 320 + (lifted ? index * 12 : 0)),
      curve: lifted ? Interval((index * 12) / (320 + index * 12), 1) : Curves.easeOut,
      builder: (context, v, child) {
        final dy = lifted ? -18 * (1 - v) : 10 * (1 - v);
        Widget w = Opacity(opacity: v, child: Transform.translate(offset: Offset(0, dy), child: child));
        final blur = 6 * (1 - v);
        if (!reduced && blur > 0.2) {
          w = ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur), child: w);
        }
        return w;
      },
      child: AnimatedDefaultTextStyle(
        duration: ms(context, 360 + index * 22),
        curve: Interval((index * 22) / (360 + index * 22), 1),
        style: PlannerType.ui(25, weight: parsed && isKey ? 500 : 400, color: parsed ? (isKey ? c.tx : c.t3) : c.tx, tracking: -0.015)
            .copyWith(height: 1.3),
        child: Text(word),
      ),
    );
  }
}

/// Result rows stagger in (fade + rise 14px, Spring).
class _Rise extends StatelessWidget {
  const _Rise({required this.on, required this.child});
  final bool on;
  final Widget child;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: on ? 1 : 0),
        duration: PlannerMotion.ms(context, 520),
        curve: const Cubic(0.34, 1.45, 0.55, 1),
        child: child,
        builder: (context, v, child) => Opacity(
          opacity: v.clamp(0, 1),
          child: Transform.translate(offset: Offset(0, 14 * (1 - v)), child: child),
        ),
      );
}
