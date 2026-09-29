import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/state/actions.dart';
import '../../app/state/clock.dart';
import '../../app/state/derived.dart';
import '../../app/state/staging.dart';
import '../../app/state/store.dart';
import '../../app/state/ui_state.dart';
import '../../app/theme/planner_theme.dart';
import '../../domain/base_day.dart';
import '../../domain/layout.dart';
import '../../domain/task.dart';
import '../../domain/time.dart';
import '../../widgets/surfaces.dart';
import '../../widgets/task_block.dart';
import 'today_model.dart';

const _timeCol = 44.0;
const _contentLeft = 52.0;

/// Today's proportional timeline (README 6.2, Strip).
class TimelineStrip extends ConsumerStatefulWidget {
  const TimelineStrip({super.key, this.ambient = true});

  /// False while voice, drag or a sheet leads: the now pulse pauses.
  final bool ambient;

  @override
  ConsumerState<TimelineStrip> createState() => _TimelineStripState();
}

class _TimelineStripState extends ConsumerState<TimelineStrip> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToNow());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scrollTo(double y, {bool animate = false}) {
    if (!_scroll.hasClients) return;
    final target = y.clamp(0.0, _scroll.position.maxScrollExtent);
    if (animate && !PlannerMotion.reduced(context)) {
      _scroll.animateTo(target,
          duration: const Duration(milliseconds: 500), curve: PlannerMotion.settleCurve);
    } else {
      _scroll.jumpTo(target);
    }
  }

  /// Now sits 150px from the top.
  void _scrollToNow() {
    final m = ref.read(todayModelProvider);
    if (!m.isToday) return;
    _scrollTo(math.max(0, nowY(m.layout.seq, ref.read(nowProvider)) - 150));
  }

  /// The placement window, or tomorrow's evening.
  double _windowTop(TodayModel m) {
    final ids = m.staging.winIds;
    final rows = ids.isNotEmpty
        ? m.layout.seq.where((x) => ids.contains(x.taskId))
        : m.layout.seq.where((x) => x.kind == ItemKind.open && x.start >= 1080);
    if (rows.isEmpty) return 0;
    return rows.map((x) => x.y).reduce(math.min);
  }

  @override
  Widget build(BuildContext context) {
    final c = PlannerColors.of(context);
    final m = ref.watch(todayModelProvider);
    final ui = ref.watch(todayUiProvider);
    final act = ref.read(actionsProvider);
    final stagingCtl = ref.read(stagingProvider.notifier);

    ref.listen(shownDayProvider, (prev, next) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (ref.read(todayModelProvider).isToday) {
          _scrollToNow();
        } else {
          _scrollTo(math.max(0, _windowTop(ref.read(todayModelProvider)) - 24));
        }
      });
    });
    ref.listen(stagingProvider.select((s) => s.winIds), (prev, next) {
      if (next.isEmpty) return;
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => _scrollTo(math.max(0, _windowTop(ref.read(todayModelProvider)) - 24), animate: true));
    });
    ref.listen(currentTabProvider, (prev, next) {
      if (next == AppTab.today && prev != AppTab.today) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToNow());
      }
    });

    final st = m.staging;
    final seq = m.layout.seq;
    final winIds = st.winIds.where(m.rowOf.containsKey).toList();

    // Window highlight during placement.
    var winTop = 0.0, winH = 0.0, winRange = '';
    if (winIds.isNotEmpty) {
      final rs = [for (final id in winIds) m.rowOf[id]!];
      final br = seq.where((x) => x.kind == ItemKind.breakTime && winIds.contains(x.parentId));
      final all = [...rs, ...br];
      winTop = all.map((x) => x.y).reduce(math.min) - 4;
      winH = all.map((x) => x.y + x.h).reduce(math.max) - winTop + 4;
      final g0 = rs.map((x) => x.start).reduce(math.min);
      final g1 = [...rs.map((x) => x.end), ...br.map((x) => x.end)].reduce(math.max);
      winRange = '${fmt(g0)} → ${fmt(g1)}';
    }
    final winShow = st.winLit && winIds.isNotEmpty;
    final winLabel = winIds.any(st.isHiddenOrStaged);
    final evGap = m.eveningGap;

    final rows = <Widget>[
      for (final it in seq)
        if (it.kind != ItemKind.task)
          _row(context, c, m, it,
              winLit: st.winLit && winIds.isNotEmpty,
              empty: it.kind == ItemKind.open &&
                  m.dayTasks.isEmpty &&
                  evGap?.id == it.id &&
                  it.h >= 110 &&
                  !st.winLit),
    ];

    // Blocks: every task laid out today, plus any flying out.
    final blocks = <Widget>[];
    for (final t in m.layout.tasks) {
      final it = m.rowOf[t.id]!;
      final pl = st.place[t.id];
      final staged = pl == PlaceStage.hidden || pl == PlaceStage.staged;
      if (!staged) stagingCtl.lastTop[t.id] = (it.y, it.h);
      blocks.add(_block(context, m, t, it, pl, winTop, act));
    }
    for (final e in st.leaving.entries) {
      if (m.rowOf.containsKey(e.key)) continue;
      final t = ref.read(plannerStoreProvider).task(e.key);
      if (t == null || !t.isScheduled) continue;
      blocks.add(_leavingBlock(context, m, t, e.value));
    }

    final phase = ui.phase;
    final dayOpacity = phase == DayPhase.inPlace ? 1.0 : 0.0;
    final dayDx = switch (phase) {
      DayPhase.outLeft || DayPhase.preLeft => -22.0,
      DayPhase.outRight || DayPhase.preRight => 22.0,
      DayPhase.inPlace => 0.0,
    };
    final instant = phase == DayPhase.preLeft || phase == DayPhase.preRight;

    return ShaderMask(
      shaderCallback: (r) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: const [Color(0x00000000), Color(0xFF000000), Color(0xFF000000), Color(0x00000000)],
        stops: [0, 14 / r.height, 1 - 24 / r.height, 1],
      ).createShader(r),
      blendMode: BlendMode.dstIn,
      child: SingleChildScrollView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 90),
        child: AnimatedOpacity(
          opacity: dayOpacity,
          duration: instant ? Duration.zero : PlannerMotion.ms(context, 200),
          child: _Xform(
            dx: dayDx,
            ms: instant ? 0 : 360,
            curve: PlannerMotion.settleCurve,
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: m.layout.height + 10),
              duration: PlannerMotion.ms(context, 620),
              curve: PlannerMotion.boardCurve,
              builder: (context, h, child) => SizedBox(height: math.max(h, m.layout.height + 10), child: child),
              child: Stack(clipBehavior: Clip.none, children: [
                ...rows,
                if (winShow)
                  _Window(
                    key: const ValueKey('window'),
                    top: winTop,
                    height: winH,
                    range: winRange,
                    labelOn: winLabel,
                    scanning: st.scanning,
                  ),
                ...blocks,
                if (m.isToday && ref.watch(currentTabProvider) == AppTab.today)
                  _NowIndicator(seq: seq, ambient: widget.ambient),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, PlannerColors c, TodayModel m, TimelineItem it,
      {required bool winLit, required bool empty}) {
    final d0 = it.end - it.start;
    final past = m.isToday && it.end <= m.now && it.kind != ItemKind.marker;
    final parentHidden =
        it.kind == ItemKind.breakTime && m.staging.isHiddenOrStaged(it.parentId ?? '');
    final labelPad = it.kind == ItemKind.marker
        ? 8.0
        : it.kind == ItemKind.protected && it.h < 34
            ? 9.0
            : it.h < 50
                ? 12.0
                : 10.0;
    final showTime = it.kind != ItemKind.breakTime && !(it.kind == ItemKind.open && winLit);
    final ms = PlannerMotion.ms;

    Widget body;
    switch (it.kind) {
      case ItemKind.fixed:
        final cat = it.cat ?? Category.work;
        body = Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(color: cat.band(c), borderRadius: BorderRadius.circular(4)),
          child: Row(children: [
            Expanded(
              child: Text(it.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: PlannerType.ui(14, color: c.tx)),
            ),
            Text(d0 > 90 ? '${fmt(it.start)} → ${fmt(it.end)}  ${dur(d0)}' : dur(d0),
                style: PlannerType.time(size: 11, color: c.t2)),
          ]),
        );
      case ItemKind.protected:
        body = Stack(children: [
          Positioned.fill(child: Hatch(color: c.ln)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(children: [
              Expanded(child: Text(it.title, style: PlannerType.ui(12.5, color: c.t2))),
              Text('${dur(d0)}, protected', style: PlannerType.time(size: 11, color: c.t3)),
            ]),
          ),
        ]);
      case ItemKind.breakTime:
        body = Row(children: [
          Expanded(child: DashedLine(color: c.ln)),
          const SizedBox(width: 10),
          Text('Break ${dur(d0)}', style: PlannerType.time(size: 11, color: c.t3)),
        ]);
      case ItemKind.open:
        body = DashedBox(
          color: c.ln,
          child: Stack(children: [
            if (empty)
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text('No plans yet.', style: PlannerType.bricolage600(18, color: c.tx)),
                    const SizedBox(height: 6),
                    Text('Tell Planner what you want to accomplish.',
                        textAlign: TextAlign.center,
                        style: PlannerType.body(size: 13, color: c.t2).copyWith(height: 1.4)),
                    const SizedBox(height: 6),
                    Text('Tap the orb, or say “Hey Planner”.',
                        textAlign: TextAlign.center, style: PlannerType.ui(12, weight: 400, color: c.t3)),
                    const SizedBox(height: 10),
                    Text('${fmt(math.max(it.start.toDouble(), m.isToday ? m.now : 0))} → ${fmt(it.end)} open',
                        style: PlannerType.time(size: 11, color: c.t3)),
                  ]),
                ),
              ),
            Positioned(
              right: 12,
              bottom: 8,
              child: AnimatedOpacity(
                opacity: winLit || empty ? 0 : 1,
                duration: const Duration(milliseconds: 300),
                child: Text('Open ${dur(d0)}', style: PlannerType.time(size: 11, color: c.t3)),
              ),
            ),
          ]),
        );
      case ItemKind.marker:
        body = Row(children: [
          Container(
            width: 7,
            height: 7,
            decoration:
                BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c.t3, width: 1.5)),
          ),
          const SizedBox(width: 10),
          Text(it.title, style: PlannerType.ui(13, color: c.t2)),
        ]);
      case ItemKind.task:
        body = const SizedBox();
    }

    final sem = switch (it.kind) {
      ItemKind.fixed => '${it.title}, ${fmt(it.start)} to ${fmt(it.end)}, fixed',
      ItemKind.protected => '${it.title}, ${dur(d0)}, protected',
      ItemKind.breakTime => 'Break, ${dur(d0)}',
      ItemKind.open => 'Open, ${fmt(it.start)} to ${fmt(it.end)}',
      ItemKind.marker => '${it.title} ${fmt(it.start)}',
      ItemKind.task => '',
    };

    return AnimatedPositioned(
      key: ValueKey('row-${it.id}'),
      duration: ms(context, 620),
      curve: PlannerMotion.boardCurve,
      left: 0,
      right: 0,
      top: it.y,
      height: it.h,
      child: AnimatedOpacity(
        duration: ms(context, 400),
        opacity: parentHidden ? 0 : past ? 0.5 : 1,
        child: Semantics(
          label: empty ? 'No plans yet. Tell Planner what you want to accomplish.' : sem,
          excludeSemantics: true,
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              width: _timeCol,
              child: Padding(
                padding: EdgeInsets.only(top: labelPad),
                child: Text(showTime ? fmt(it.start) : '',
                    style: PlannerType.time(size: 11, weight: 500, color: c.t3)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: body),
          ]),
        ),
      ),
    );
  }

  Widget _block(BuildContext context, TodayModel m, Task t, TimelineItem it, PlaceStage? pl,
      double winTop, PlannerActions act) {
    final c = PlannerColors.of(context);
    final st = m.staging;
    final ph = st.sweeping[t.id];
    final vDone = t.done && ph != SweepPhase.pre && ph != SweepPhase.a;
    final missed = m.isMissedTask(t);
    final isCur = m.cur?.id == t.id, isNext = m.next?.id == t.id;
    final staged = pl == PlaceStage.hidden || pl == PlaceStage.staged;
    final full = (isCur || isNext) && !vDone && !missed && !staged;
    var top = it.y, h = it.h, opacity = 1.0, inset = 0.0;
    var dy = 0.0, scale = 1.0;
    if (staged) {
      top = winTop + 12;
      h = 44;
      inset = 0.16;
      opacity = pl == PlaceStage.hidden ? 0 : 1;
      if (pl == PlaceStage.hidden) {
        dy = -10;
        scale = 0.92;
      }
    }
    final r = m.routine;
    final ov = math.max(0, math.min(t.end!, r.sleep) - math.max(t.start!, r.sleep - 30));
    final canCheck = m.isToday && !missed && !staged;
    final look = TaskBlockLook(
      task: t,
      height: h,
      isCurrent: isCur,
      isNext: isNext,
      missed: missed,
      staged: staged,
      visuallyDone: vDone,
      sweepScale: ph == SweepPhase.a || ph == SweepPhase.b,
      sweepVisible: ph == SweepPhase.a,
      checkPop: ph == SweepPhase.a,
      fresh: st.fresh.containsKey(t.id),
      canCheck: canCheck,
      canSwipe: canCheck && !t.done,
      elapsed: isCur ? (m.now - t.start!) / (t.end! - t.start!) : 0,
      windDownMinutes: ov.toInt(),
    );
    final ms = PlannerMotion.ms;
    return AnimatedPositioned(
      key: ValueKey('blk-${t.id}'),
      duration: ms(context, 640),
      curve: PlannerMotion.springCurve,
      left: 0,
      right: 0,
      top: top,
      height: h,
      child: IgnorePointer(
        ignoring: staged,
        child: AnimatedOpacity(
          duration: ms(context, 380),
          opacity: opacity,
          child: _Xform(
            dy: dy,
            scale: scale,
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(
                width: _timeCol,
                child: AnimatedOpacity(
                  opacity: staged ? 0 : 1,
                  duration: const Duration(milliseconds: 300),
                  child: Padding(
                    padding: EdgeInsets.only(top: h < 50 ? 14 : 12),
                    child: Text(fmt(t.start!),
                        style: PlannerType.time(size: 11, weight: 500, color: full ? c.tx : c.t3)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: LayoutBuilder(builder: (context, box) {
                  final ins = box.maxWidth * inset;
                  return Stack(children: [
                    AnimatedPositioned(
                      duration: ms(context, 640),
                      curve: PlannerMotion.springCurve,
                      left: ins,
                      right: ins,
                      top: 0,
                      bottom: 0,
                      child: TaskBlock(
                        look: look,
                        onOpen: () => act.openBlock(t.id),
                        onComplete: ({required fromSwipe}) => act.toggle(t.id, fromSwipe: fromSwipe),
                        onReschedule: () => act.openDecision(t.id, reschedule: !missed),
                      ),
                    ),
                  ]);
                }),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  /// A block that already moved in the data, drawn at its old spot: lifts
  /// to 1.02, then flies (96, −40) at 0.5 scale while fading.
  Widget _leavingBlock(BuildContext context, TodayModel m, Task t, LeavingInfo l) {
    final lift = l.phase == LeavePhase.lift;
    return AnimatedPositioned(
      key: ValueKey('blk-${t.id}'),
      duration: PlannerMotion.ms(context, 640),
      left: 0,
      right: 0,
      top: l.y,
      height: l.h,
      child: IgnorePointer(
        child: AnimatedOpacity(
          duration: PlannerMotion.ms(context, 380),
          opacity: lift ? 1 : 0,
          child: _Xform(
            dx: lift ? 0 : 96,
            dy: lift ? 0 : -40,
            scale: lift ? 1.02 : 0.5,
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const SizedBox(width: _timeCol + 8),
              Expanded(
                child: TaskBlock(
                  look: TaskBlockLook(task: t, height: l.h, canCheck: false),
                  onOpen: () {},
                  onComplete: ({required fromSwipe}) {},
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Transform tween (560ms Cubic(.4, 0, .2, 1)), origin 70% 50%.
class _Xform extends StatelessWidget {
  const _Xform({
    this.dx = 0,
    this.dy = 0,
    this.scale = 1,
    this.ms = 560,
    this.curve = const Cubic(0.4, 0, 0.2, 1),
    required this.child,
  });
  final double dx, dy, scale;
  final int ms;
  final Curve curve;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<List<double>>(
        tween: _ListTween(end: [dx, dy, scale]),
        duration: PlannerMotion.ms(context, ms),
        curve: curve,
        child: child,
        builder: (context, v, child) => Transform(
          alignment: const Alignment(0.4, 0),
          transform: Matrix4.identity()
            ..translateByDouble(v[0], v[1], 0, 1)
            ..scaleByDouble(v[2], v[2], 1, 1),
          child: child,
        ),
      );
}

class _ListTween extends Tween<List<double>> {
  _ListTween({required List<double> end}) : super(begin: end, end: end);
  @override
  List<double> lerp(double t) =>
      [for (var i = 0; i < end!.length; i++) begin![i] + (end![i] - begin![i]) * t];
}

/// The placement window: s1 fill, t3 hairline, a scan line sweeping it
/// (800ms), and its range "20:00 → 00:00 open".
class _Window extends StatefulWidget {
  const _Window({
    super.key,
    required this.top,
    required this.height,
    required this.range,
    required this.labelOn,
    required this.scanning,
  });
  final double top, height;
  final String range;
  final bool labelOn, scanning;

  @override
  State<_Window> createState() => _WindowState();
}

class _WindowState extends State<_Window> with SingleTickerProviderStateMixin {
  late final _scan = AnimationController(vsync: this);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.scanning) _run();
    });
  }

  @override
  void didUpdateWidget(_Window old) {
    super.didUpdateWidget(old);
    if (widget.scanning && !old.scanning) _run();
  }

  void _run() {
    if (!mounted) return;
    _scan
      ..duration = PlannerMotion.ms(context, 800)
      ..forward(from: 0);
  }

  @override
  void dispose() {
    _scan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = PlannerColors.of(context);
    return AnimatedPositioned(
      duration: PlannerMotion.ms(context, 400),
      left: _contentLeft,
      right: 0,
      top: widget.top,
      height: widget.height,
      child: Container(
        decoration: BoxDecoration(
          color: c.s1,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: c.t3, width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(children: [
          AnimatedBuilder(
            animation: _scan,
            builder: (context, _) {
              final v = const Cubic(0.4, 0, 0.2, 1).transform(_scan.value);
              final o = _scan.isAnimating
                  ? (_scan.value < 0.12
                      ? _scan.value / 0.12
                      : _scan.value > 0.88
                          ? (1 - _scan.value) / 0.12
                          : 1.0)
                  : 0.0;
              return Positioned(
                left: 0,
                right: 0,
                top: v * (widget.height - 2),
                height: 2,
                child: Opacity(opacity: o.clamp(0, 1), child: ColoredBox(color: c.tx)),
              );
            },
          ),
          Positioned(
            left: 12,
            bottom: 10,
            child: AnimatedOpacity(
              opacity: widget.labelOn ? 1 : 0,
              duration: const Duration(milliseconds: 300),
              child: Text('${widget.range} open', style: PlannerType.time(size: 11, weight: 500, color: c.t2)),
            ),
          ),
        ]),
      ),
    );
  }
}

/// `NowIndicator`: tx pill 44 × 20 with HH:mm, 1.5px line, an 8px dot
/// pulsing on Drift. Moves linearly each second.
class _NowIndicator extends ConsumerStatefulWidget {
  const _NowIndicator({required this.seq, required this.ambient});
  final List<TimelineItem> seq;
  final bool ambient;
  @override
  ConsumerState<_NowIndicator> createState() => _NowIndicatorState();
}

class _NowIndicatorState extends ConsumerState<_NowIndicator> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(vsync: this, duration: PlannerMotion.drift);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_NowIndicator old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final run = widget.ambient && !PlannerMotion.reduced(context);
    if (run && !_pulse.isAnimating) {
      _pulse.repeat();
    } else if (!run && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 1;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = PlannerColors.of(context);
    final now = ref.watch(nowProvider);
    final y = nowY(widget.seq, now);
    return AnimatedPositioned(
      duration: const Duration(seconds: 1),
      left: 0,
      right: 0,
      top: y,
      height: 0,
      child: IgnorePointer(
        child: Semantics(
          label: 'Now, ${fmt(now)}',
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned(
              left: 0,
              top: -10,
              width: 44,
              height: 20,
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(color: c.tx, borderRadius: BorderRadius.circular(4)),
                child: Text(fmt(now), style: PlannerType.time(size: 11, weight: 600, color: c.bg)),
              ),
            ),
            Positioned(left: 52, right: 0, top: -0.75, height: 1.5, child: ColoredBox(color: c.tx)),
            Positioned(
              left: 48,
              top: -4,
              width: 8,
              height: 8,
              child: DecoratedBox(decoration: BoxDecoration(color: c.tx, shape: BoxShape.circle)),
            ),
            Positioned(
              left: 48,
              top: -4,
              width: 8,
              height: 8,
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (context, _) {
                  final v = const Cubic(0.2, 0.6, 0.3, 1).transform(_pulse.value);
                  return Opacity(
                    opacity: widget.ambient ? (0.55 * (1 - v)).clamp(0, 1) : 0,
                    child: Transform.scale(
                      scale: 1 + 2.4 * v,
                      child: DecoratedBox(decoration: BoxDecoration(color: c.tx, shape: BoxShape.circle)),
                    ),
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
