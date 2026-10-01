import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/shell.dart';
import '../../app/state/actions.dart';
import '../../app/state/clock.dart';
import '../../app/state/derived.dart';
import '../../app/state/sequencer.dart';
import '../../app/state/store.dart';
import '../../app/state/ui_state.dart';
import '../../app/theme/planner_theme.dart';
import '../../domain/layout.dart';
import '../../domain/onboarding.dart';
import '../../widgets/controls.dart';
import '../../widgets/icons.dart';
import '../notifications/notification_service.dart';
import '../voice/wake_word.dart';
import 'onboarding_widgets.dart';

/// Onboarding (README 6.1): five questions, then the first weekday assembles
/// itself. First launch opens here; Settings › Edit routine re-runs it
/// prefilled ([edit]). The routine commits at "Build my rhythm"; the
/// assembly only explains it.
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key, this.edit = false});
  final bool edit;

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  late OnboardingDraft _d;
  final _seq = Sequencer();
  final _title = TextEditingController();
  late final ShellCovered _covered = ref.read(shellCoveredProvider.notifier);

  /// Assembly rows revealed so far (240ms apart).
  int _built = 0;
  bool _saving = false, _failed = false, _out = false;

  @override
  void initState() {
    super.initState();
    _d = widget.edit ? OnboardingDraft.from(ref.read(routineProvider)) : const OnboardingDraft();
    WidgetsBinding.instance.addPostFrameCallback((_) => _covered.set(true));
  }

  @override
  void dispose() {
    _seq.clear();
    _title.dispose();
    final covered = _covered;
    scheduleMicrotask(() => covered.set(false));
    super.dispose();
  }

  void _set(OnboardingDraft d) => setState(() => _d = d);

  Future<void> _next() async {
    if (_d.step < kObCommitStep) return _set(_d.next());
    if (_saving) return;
    setState(() => _saving = true);
    final ok = await ref.read(actionsProvider).applyRoutine(_d.toRoutine());
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _saving = false;
        _failed = true;
      });
      return;
    }
    final m = PlannerMotion.factor(context, reducedFactor: 0.1);
    setState(() {
      _saving = false;
      _failed = false;
      _d = _d.next();
      _built = 0;
    });
    for (var i = 1; i <= 9; i++) {
      _seq.at(300 + i * 240 * m, () => setState(() => _built = i));
    }
  }

  void _back() {
    if (_d.canBack) {
      _set(_d.back());
    } else if (widget.edit && _d.step < kObBuildStep) {
      _close();
    }
  }

  /// Edit routine › close: nothing was changed.
  void _close() => ref.read(actionsProvider).goTab(AppTab.settings);

  /// "Open Today": onboarding scales to 1.03 and blurs out while Today
  /// scales in from 0.98 (Settle).
  void _open() {
    if (_out) return;
    setState(() => _out = true);
    final m = ref.read(motionFactorProvider);
    _seq.at(380 * m, () {
      final act = ref.read(actionsProvider);
      ref.read(entrancePendingProvider.notifier).set(true);
      ref.read(todayUiProvider.notifier).set((u) => u.copyWith(dayOffset: 0, phase: DayPhase.inPlace));
      act.goTab(AppTab.today);
      if (widget.edit) {
        act.seq.at(40, () => act.note.say('Routine updated. Planner rebuilt your week around it.'));
      } else {
        // First run: a calm moment to ask for notifications. Read now: this
        // page is gone by the time the prompt shows.
        final notes = ref.read(notificationServiceProvider);
        act.seq.at(1200, notes.requestPermission);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = PlannerColors.of(context);
    final reduced = PlannerMotion.reduced(context);
    final inset = MediaQuery.paddingOf(context).bottom;
    final bottomPad = math.max(16.0, 40 - inset);
    final page = _d.step == kObBuildStep ? _assembly(bottomPad) : _questions(bottomPad);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: c.bg,
        body: TweenAnimationBuilder<double>(
          tween: Tween(end: _out ? 1 : 0),
          duration: PlannerMotion.ms(context, 420),
          builder: (context, v, child) {
            Widget w = Opacity(
              opacity: 1 - Curves.ease.transform(math.min(1, v * 420 / 380)),
              child: Transform.scale(scale: 1 + 0.03 * PlannerMotion.settleCurve.transform(v), child: child),
            );
            if (!reduced && v > 0) {
              final s = 8 * v;
              w = ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: s, sigmaY: s), child: w);
            }
            return IgnorePointer(ignoring: _out, child: w);
          },
          child: SafeArea(bottom: false, child: page),
        ),
      ),
    );
  }

  // ------------------------------------------------------------ questions

  Widget _questions(double bottomPad) {
    final c = PlannerColors.of(context);
    final step = _d.step;
    final switchMs = PlannerMotion.ms(context, 240);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 12),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: ObSegments(step: step)),
      const SizedBox(height: 11),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: SizedBox(
          height: 44,
          child: Row(children: [
            if (_d.canBack)
              PlannerIconButton(icon: PIcon.back, label: 'Back', onTap: _back, color: c.t2, size: 20),
            const Spacer(),
            if (widget.edit)
              PlannerIconButton(
                  icon: PIcon.close, label: 'Close, keep the current routine', onTap: _close, color: c.t2, size: 20),
          ]),
        ),
      ),
      const SizedBox(height: 16),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: AnimatedSwitcher(
          duration: switchMs,
          layoutBuilder: (cur, prev) => Stack(alignment: Alignment.topLeft, children: [...prev, ?cur]),
          child: Column(
            key: ValueKey(step),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(obQuestions[step], style: PlannerType.question(color: c.tx)),
              ),
              const SizedBox(height: 10),
              Text(obSubtitles[step], style: PlannerType.body(size: 14, color: c.t2)),
            ],
          ),
        ),
      ),
      Expanded(child: _d.isTimeStep ? _timeBody() : _commitBody()),
      Padding(
        padding: EdgeInsets.fromLTRB(24, 12, 24, bottomPad + MediaQuery.paddingOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          PrimaryPill(
            label: step == kObCommitStep ? 'Build my rhythm' : 'Continue',
            height: 52,
            expand: true,
            loading: _saving,
            onTap: _next,
          ),
          if (_failed)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Semantics(
                liveRegion: true,
                child: Text('Not saved, tap to retry', style: PlannerType.ui(12, weight: 400, color: c.t2)),
              ),
            ),
        ]),
      ),
    ]);
  }

  Widget _timeBody() {
    final c = PlannerColors.of(context);
    final v = _d.value!;
    final today = ref.watch(todayProvider);
    return LayoutBuilder(builder: (context, box) {
      return SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: IntrinsicHeight(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const SizedBox(height: 20),
              ObTimeReadout(
                value: v,
                question: obQuestions[_d.step],
                onMinus: () => _set(_d.nudge(-15)),
                onPlus: () => _set(_d.nudge(15)),
              ),
              const SizedBox(height: 28),
              Center(child: ObRuler(value: v, onDrag: (from, dx) => _set(_d.drag(from, dx)))),
              const SizedBox(height: 8),
              Text('Drag the ruler, or use − and +',
                  textAlign: TextAlign.center, style: PlannerType.ui(12, weight: 400, color: c.t3)),
              const SizedBox(height: 16),
              SizedBox(
                height: 44,
                child: _d.step == 1
                    ? Center(
                        child: PlannerChip(
                          label: 'I don’t work fixed hours',
                          selected: _d.noWork,
                          onTap: () => _set(_d.toggleNoWork()),
                        ),
                      )
                    : null,
              ),
              const Spacer(),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ObDayBar(draft: _d, day: firstWeekday(today), width: box.maxWidth - 40),
              ),
              const SizedBox(height: 16),
            ]),
          ),
        ),
      );
    });
  }

  Widget _commitBody() {
    final cu = _d.custom;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      children: [
        for (final cm in _d.commitments) ...[
          ObCommitRow(commitment: cm, onTap: () => _set(_d.flip(cm.id))),
          const SizedBox(height: 8),
        ],
        if (cu != null) ...[
          ObCustomForm(
            value: cu,
            controller: _title,
            onEdit: (f) => _set(_d.editCustom(f)),
            onAdd: () {
              _set(_d.addCustom('cu${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'));
              _title.clear();
            },
            onCancel: () {
              _set(_d.cancelCustom());
              _title.clear();
            },
          ),
          const SizedBox(height: 8),
        ] else
          ObAddOwn(onTap: () => _set(_d.openCustom())),
      ],
    );
  }

  // ------------------------------------------------------------- assembly

  Widget _assembly(double bottomPad) {
    final c = PlannerColors.of(context);
    final today = ref.watch(todayProvider);
    final routine = ref.watch(plannerStoreProvider.select((d) => d.routine));
    final rows = buildDay(firstWeekday(today), routine, const []).seq;
    final ready = _built >= math.min(9, rows.length + 1);
    Widget rise(Widget child, {int delay = 0}) => _Rise(on: ready, delay: delay, child: child);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 48),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Semantics(
          header: true,
          liveRegion: true,
          child: Text(ready ? 'Your rhythm is ready.' : 'Building your rhythm',
              style: PlannerType.question(color: c.tx)),
        ),
      ),
      const SizedBox(height: 8),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: rise(Text(rhythmCopy(routine, today), style: PlannerType.body(size: 14, color: c.t2))),
      ),
      const SizedBox(height: 36),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (i, x) in rows.indexed) ...[
              if (i > 0) const SizedBox(height: 5),
              ObAssemblyRow(item: x, on: i < _built),
            ],
          ]),
        ),
      ),
      Padding(
        padding: EdgeInsets.fromLTRB(24, 16, 24, bottomPad + MediaQuery.paddingOf(context).bottom),
        child: rise(
          PrimaryPill(label: 'Open Today', height: 52, expand: true, onTap: ready ? _open : null),
          delay: 200,
        ),
      ),
    ]);
  }
}

/// Fades in and rises 12px on Spring once [on] (the "ready" state).
class _Rise extends StatelessWidget {
  const _Rise({required this.on, required this.child, this.delay = 0});
  final bool on;
  final int delay;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final total = 640 + delay;
    return ExcludeSemantics(
      excluding: !on,
      child: IgnorePointer(
        ignoring: !on,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: on ? 1 : 0),
          duration: PlannerMotion.ms(context, total),
          builder: (context, t, child) {
            // Delay, then 400ms opacity and 640ms Spring rise.
            final ms = t * total - delay;
            final o = (ms / 400).clamp(0.0, 1.0);
            final r = PlannerMotion.springCurve.transform((ms / 640).clamp(0.0, 1.0));
            return Opacity(
              opacity: on ? o : 0,
              child: Transform.translate(offset: Offset(0, 12 * (1 - (on ? r : 0))), child: child),
            );
          },
          child: child,
        ),
      ),
    );
  }
}
