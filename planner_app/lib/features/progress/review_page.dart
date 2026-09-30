import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/state/actions.dart';
import '../../app/state/clock.dart';
import '../../app/state/derived.dart';
import '../../app/state/store.dart';
import '../../app/theme/planner_theme.dart';
import '../../domain/progress.dart';
import '../../domain/time.dart';
import '../../widgets/controls.dart';
import '../../widgets/icons.dart';
import '../voice/wake_word.dart';
import 'heatmap.dart';
import 'ribbon.dart';

/// Weekly review (README 6.9): six staged screens. Tap the right side (or →)
/// to advance and the left side (or ←) to go back; close top right or Esc.
class ReviewPage extends ConsumerStatefulWidget {
  const ReviewPage({super.key});

  @override
  ConsumerState<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends ConsumerState<ReviewPage> with SingleTickerProviderStateMixin {
  static const _stages = 6;
  int _stage = 0;

  /// Milliseconds since the current stage came in (drives every stagger).
  late final AnimationController _in = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));
  late final ShellCovered _covered = ref.read(shellCoveredProvider.notifier);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _covered.set(true);
      if (mounted) _start();
    });
  }

  @override
  void dispose() {
    _in.dispose();
    final covered = _covered;
    scheduleMicrotask(() => covered.set(false));
    super.dispose();
  }

  void _start() {
    _in.duration = PlannerMotion.ms(context, 2400);
    _in.forward(from: 0);
  }

  void _go(int n) {
    if (n < 0) return;
    if (n >= _stages) return _close();
    setState(() => _stage = n);
    _in.value = 0;
    Future.delayed(PlannerMotion.ms(context, 40), () {
      if (mounted) _start();
    });
  }

  void _close() {
    final r = GoRouter.maybeOf(context);
    if (r != null && r.canPop()) r.pop();
  }

  KeyEventResult _key(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.arrowRight) {
      _go(_stage + 1);
    } else if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _go(_stage - 1);
    } else if (e.logicalKey == LogicalKeyboardKey.escape) {
      _close();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final c = PlannerColors.of(context);
    final p = ref.watch(weekProgressProvider);
    final inset = MediaQuery.paddingOf(context);
    return Scaffold(
      backgroundColor: c.bg,
      body: Focus(
        autofocus: true,
        onKeyEvent: _key,
        child: Semantics(
          scopesRoute: true,
          namesRoute: true,
          explicitChildNodes: true,
          label: 'Weekly review',
          child: AnimatedBuilder(
            animation: _in,
            builder: (context, _) {
              final t = _in.value * 2400;
              return Stack(children: [
                // Tap regions: left 30% back, right 70% forward.
                Positioned(
                  left: 0,
                  top: inset.top + 54,
                  bottom: 0,
                  width: MediaQuery.sizeOf(context).width * 0.3,
                  child: Semantics(
                    button: true,
                    label: 'Previous',
                    onTap: () => _go(_stage - 1),
                    child: GestureDetector(
                        behavior: HitTestBehavior.opaque, excludeFromSemantics: true, onTap: () => _go(_stage - 1)),
                  ),
                ),
                Positioned(
                  right: 0,
                  top: inset.top + 54,
                  bottom: 0,
                  width: MediaQuery.sizeOf(context).width * 0.7,
                  child: Semantics(
                    button: true,
                    label: 'Next',
                    onTap: () => _go(_stage + 1),
                    child: GestureDetector(
                        behavior: HitTestBehavior.opaque, excludeFromSemantics: true, onTap: () => _go(_stage + 1)),
                  ),
                ),
                Positioned(
                  top: inset.top + 8,
                  left: 20,
                  right: 20,
                  child: IgnorePointer(child: _segments(c, t)),
                ),
                Positioned(
                  top: inset.top + 18,
                  right: 10,
                  child: PlannerIconButton(icon: PIcon.close, label: 'Close review', onTap: _close, color: c.tx, size: 20),
                ),
                Positioned(
                  top: inset.top + 84,
                  left: 24,
                  right: 24,
                  bottom: inset.bottom + 40,
                  child: _entrance(
                    t,
                    _stage == _stages - 1
                        ? _stageBody(c, p, t)
                        // Long weeks clip rather than overflow.
                        : IgnorePointer(
                            child: SingleChildScrollView(
                                physics: const NeverScrollableScrollPhysics(), child: _stageBody(c, p, t)),
                          ),
                  ),
                ),
              ]);
            },
          ),
        ),
      ),
    );
  }

  Widget _segments(PlannerColors c, double t) => Row(children: [
        for (var i = 0; i < _stages; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: Container(
              height: 3,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(color: c.ln, borderRadius: BorderRadius.circular(2)),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: i < _stage
                    ? 1
                    : i == _stage
                        ? PlannerMotion.settleCurve.transform((t / 900).clamp(0.0, 1.0))
                        : 0,
                child: ColoredBox(color: c.tx),
              ),
            ),
          ),
        ],
      ]);

  /// Each stage fades in and rises 16px on Spring.
  Widget _entrance(double t, Widget child) {
    final o = (t / 420).clamp(0.0, 1.0);
    final r = PlannerMotion.springCurve.transform((t / 640).clamp(0.0, 1.0));
    return Opacity(opacity: o, child: Transform.translate(offset: Offset(0, 16 * (1 - r)), child: child));
  }

  /// Opacity and a small slide for staggered pieces: [delay] then [ms].
  static double _p(double t, num delay, num ms) => ((t - delay) / ms).clamp(0.0, 1.0);

  Widget _stageBody(PlannerColors c, WeekProgress p, double t) {
    final h1 = PlannerType.bricolage600(40, height: 1.05, tracking: -0.02, color: c.tx);
    final sub = PlannerType.body(size: 15, color: c.t2).copyWith(height: 1.5);
    final today = ref.read(todayProvider);
    switch (_stage) {
      case 0:
        return IgnorePointer(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(weekRange(today), style: PlannerType.time(size: 12, weight: 500, color: c.t3)),
            const SizedBox(height: 12),
            Semantics(header: true, child: Text('Your week, as it happened.', style: PlannerType.display(color: c.tx))),
            const SizedBox(height: 12),
            Text(reviewIntro(p), style: sub),
            const SizedBox(height: 34),
            CategoryRibbon(
              progress: p,
              withWork: false,
              reveal: PlannerMotion.settleCurve.transform(_p(t, 200, 1600)),
            ),
            const SizedBox(height: 12),
            Text('The dashed outline is what you planned. Tap to continue.',
                style: PlannerType.ui(12, weight: 400, color: c.t3)),
          ]),
        );
      case 1:
        final squares = [...p.doneTasks, ...p.plannedTasks.where((x) => !x.done)].take(48).toList();
        final n = p.plannedCount;
        return IgnorePointer(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Semantics(
              header: true,
              child: Text(n == 0 ? 'A quiet week.' : 'You planned $n ${plural(n, 'task')}.', style: h1),
            ),
            const SizedBox(height: 14),
            Text(n == 0 ? 'Nothing was planned.' : 'You finished ${p.doneCount}.', style: h1.copyWith(color: c.t2)),
            const SizedBox(height: 32),
            LayoutBuilder(builder: (context, box) {
              final w = (box.maxWidth - 7 * 6) / 8;
              return Wrap(spacing: 6, runSpacing: 6, children: [
                for (final (i, x) in squares.indexed)
                  Opacity(
                    opacity: _p(t, 300 + i * 45, 200),
                    child: Container(
                      width: w,
                      height: w,
                      decoration: BoxDecoration(
                        color: x.done
                            ? x.cat.color.withValues(alpha: _p(t, 300 + i * 45, 300))
                            : null,
                        border: Border.all(color: x.done ? x.cat.color : c.t3, width: 1.5),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
              ]);
            }),
            const SizedBox(height: 22),
            Text(reviewCompletion(p, firstWeek: _firstWeek()), style: sub),
          ]),
        );
      case 2:
        final bars = [Category.study, Category.build, Category.self];
        final maxM = math.max(1, bars.map(p.catTotal).reduce(math.max));
        return IgnorePointer(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(dur(p.focusedMinutes), style: PlannerType.numeral(72, color: c.tx)),
            const SizedBox(height: 14),
            Semantics(
                header: true, child: Text('of focused time.', style: PlannerType.bricolage600(28, height: 1.1, color: c.tx))),
            const SizedBox(height: 14),
            Text('Study, Build and Self: the hours you chose for yourself, outside work.', style: sub),
            const SizedBox(height: 32),
            for (final (i, cat) in bars.indexed) ...[
              if (i > 0) const SizedBox(height: 14),
              Row(children: [
                Expanded(child: Text(cat.label, style: PlannerType.ui(14, color: c.tx))),
                Text(dur(p.catTotal(cat)), style: PlannerType.time(size: 13, color: c.t2)),
              ]),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: p.catTotal(cat) / maxM *
                      const Cubic(0.34, 1.2, 0.55, 1).transform(_p(t, 200 + i * 160, 900)),
                  child: Container(
                    height: 10,
                    decoration: BoxDecoration(color: cat.color, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
              ),
            ],
          ]),
        );
      case 3:
        final moves = reviewMoves(p);
        final none = moves.every((m) => m.$2 == 0);
        return IgnorePointer(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Semantics(header: true, child: Text(none ? 'Nothing moved.' : 'Some things moved.', style: h1)),
            const SizedBox(height: 14),
            Text(
                none
                    ? 'Everything happened when you planned it.'
                    : 'That’s the plan working. Nothing was dropped without you deciding.',
                style: sub),
            const SizedBox(height: 28),
            for (final (i, (k, n, d)) in moves.indexed)
              Opacity(
                opacity: _p(t, 250 + i * 180, 300),
                child: Transform.translate(
                  offset: Offset(-14 * (1 - PlannerMotion.springCurve.transform(_p(t, 250 + i * 180, 560))), 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(border: Border(top: BorderSide(color: c.ln))),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox(
                        width: 64,
                        child: Text('$n', style: PlannerType.numeral(40, color: c.tx).copyWith(height: 1)),
                      ),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(k, style: PlannerType.bricolage600(16, color: c.tx)),
                          const SizedBox(height: 3),
                          Text(d, style: PlannerType.body(size: 13, color: c.t2)),
                        ]),
                      ),
                    ]),
                  ),
                ),
              ),
          ]),
        );
      case 4:
        final (title, line) = reviewBestHours(p);
        final ma = p.mostActive, big = p.biggestDay;
        final rows = [for (var r = p.firstDay - p.weekStart; r <= p.today - p.weekStart; r++) r];
        Widget card(String label, Widget value, String meta) => Expanded(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: c.s1, borderRadius: BorderRadius.circular(4)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, style: PlannerType.ui(12, weight: 400, color: c.t2)),
                  const SizedBox(height: 3),
                  value,
                  const SizedBox(height: 3),
                  Text(meta, style: PlannerType.time(size: 12, color: c.t3)),
                ]),
              ),
            );
        return IgnorePointer(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Semantics(
                header: true,
                child: Text(title, style: PlannerType.bricolage600(36, height: 1.08, tracking: -0.02, color: c.tx))),
            const SizedBox(height: 14),
            Text(line, style: sub),
            const SizedBox(height: 28),
            FocusHeatmap(progress: p, t: t, rows: rows, cellHeight: 13, stagger: 9, labels: false, bracket: false),
            const SizedBox(height: 10),
            IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                card(
                  'Most active',
                  Row(children: [
                    if (ma != null) ...[CatSquare(ma.$1.color, size: 8), const SizedBox(width: 8)],
                    Text(ma?.$1.label ?? 'Nothing yet', style: PlannerType.bricolage600(17, color: c.tx)),
                  ]),
                  ma == null ? '0m' : dur(ma.$2),
                ),
                const SizedBox(width: 10),
                card(
                  'Biggest day',
                  Text(big == null ? 'Nothing yet' : dayLongNames[big.$1], style: PlannerType.bricolage600(17, color: c.tx)),
                  big == null ? '0m' : '${dur(big.$2)} of your time',
                ),
              ]),
            ),
          ]),
        );
      default:
        final ahead = stableSorted(ref.read(deadlinesProvider).where((d) => d.day > today), (a, b) => a.day - b.day);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          IgnorePointer(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Semantics(header: true, child: Text('Coming up.', style: h1)),
              const SizedBox(height: 14),
              Text(reviewAhead(p.carried.length, ahead.length), style: sub),
              const SizedBox(height: 22),
              for (final d in ahead.take(4))
                Semantics(
                  label: '${d.title}, due ${dayShortMonth(d.day)}',
                  excludeSemantics: true,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(border: Border(top: BorderSide(color: c.ln))),
                    child: Row(children: [
                      CatSquare(d.cat.color, size: 8),
                      const SizedBox(width: 10),
                      Expanded(child: Text(d.title, style: PlannerType.bricolage600(16, color: c.tx))),
                      Text(dayShortMonth(d.day), style: PlannerType.time(size: 12, color: c.t2)),
                    ]),
                  ),
                ),
            ]),
          ),
          const Spacer(),
          PrimaryPill(label: 'Plan next week', height: 52, expand: true, onTap: _planNext),
          const SizedBox(height: 8),
          Center(child: TextPill(label: 'Done', height: 48, onTap: _close)),
        ]);
    }
  }

  bool _firstWeek() {
    final installed = ref.read(plannerStoreProvider.select((d) => d.installedDay));
    return installed == null || ref.read(todayProvider) - installed < 7;
  }

  void _planNext() => ref.read(actionsProvider).planNextWeek();
}
