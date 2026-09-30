import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/state/actions.dart';
import '../../app/state/clock.dart';
import '../../app/state/derived.dart';
import '../../app/state/staging.dart';
import '../../app/theme/planner_theme.dart';
import '../../domain/base_day.dart';
import '../../domain/capacity.dart';
import '../../domain/layout.dart';
import '../../domain/routine.dart';
import '../../domain/scheduler.dart';
import '../../domain/task.dart';
import '../../domain/time.dart';
import '../../widgets/task_focus.dart';
import '../../widgets/surfaces.dart';

/// Board geometry (prototype `geo()`), scaled to the available width.
/// 06:00 → 24:00 in 432px (0.4 px/min) under a 44px header, 26px axis.
class BoardGeo {
  BoardGeo({
    required this.width,
    required this.week,
    required this.sel,
    required this.start,
    this.allExpanded = false,
  }) {
    gap = week || allExpanded ? 4 : 3;
    collapsed = week ? 26 : 12;
    final wb = width - ax;
    if (allExpanded) {
      expanded = (wb - 6 * gap) / 7;
    } else {
      expanded = wb - 6 * collapsed - 6 * gap;
    }
    var x = ax;
    for (var i = 0; i < 7; i++) {
      final w = allExpanded || start + i == sel ? expanded : collapsed;
      xs.add(x);
      ws.add(w);
      x += w + gap;
    }
  }

  static const ax = 26.0, hb = 44.0, bh = 432.0, k = 432 / 1080;
  final double width;
  final bool week, allExpanded;
  final int sel, start;
  late final double gap, collapsed, expanded;
  final xs = <double>[], ws = <double>[];

  double get height => hb + bh + 8;
  bool isExpanded(int day) => allExpanded || day == sel;
  double x(int day) => xs[day - start];
  double w(int day) => ws[day - start];
  bool contains(int day) => day >= start && day < start + 7;
  double yOf(num m) => hb + (m.clamp(360, 1440) - 360) * k;

  /// The column under board x [px] (±2px of slack), or null.
  int? dayAt(double px) {
    for (var i = 0; i < 7; i++) {
      if (px >= xs[i] - 2 && px < xs[i] + ws[i] + 2) return start + i;
    }
    return null;
  }
}

class _Drag {
  _Drag(this.id, this.origin);
  final String id;
  final Task origin;
  double dx = 0, dy = 0;
  int day = 0, start = 0;
}

/// `WeekBoard(days, selected, mode)`: one Stack, every mark keyed by id so
/// moves and zooms are the same animation.
class PlanBoard extends ConsumerStatefulWidget {
  const PlanBoard({
    super.key,
    required this.sel,
    required this.week,
    this.allExpanded = false,
    this.showEmpty = true,
  });

  final int sel;
  final bool week;

  /// Desktop: all seven days expanded.
  final bool allExpanded;
  final bool showEmpty;

  @override
  ConsumerState<PlanBoard> createState() => _PlanBoardState();
}

class _PlanBoardState extends ConsumerState<PlanBoard> {
  final _key = GlobalKey();
  _Drag? _drag;

  Offset _local(Offset global) {
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    return box == null ? global : box.globalToLocal(global);
  }

  void _begin(Task t) {
    if (t.done) return;
    HapticFeedback.selectionClick();
    setState(
      () => _drag = _Drag(t.id, t)
        ..day = t.day!
        ..start = t.start!,
    );
  }

  void _move(
    BoardGeo g,
    Offset delta,
    Offset global,
    Routine r,
    int today,
    num now,
  ) {
    final d = _drag;
    if (d == null) return;
    final t = d.origin;
    final px = _local(global).dx;
    var hd = g.dayAt(px) ?? t.day!;
    if (hd < today) hd = today;
    final dd = t.end! - t.start!;
    final st = snapDrop(
      (t.start! + delta.dy / BoardGeo.k).round(),
      dd,
      r,
      isToday: hd == today,
      now: now,
    );
    setState(() {
      d
        ..dx = delta.dx
        ..dy = delta.dy
        ..day = hd
        ..start = st;
    });
  }

  void _end() {
    final d = _drag;
    if (d == null) return;
    setState(() => _drag = null);
    ref.read(actionsProvider).dropOnBoard(d.id, d.day, d.start);
  }

  @override
  Widget build(BuildContext context) {
    final c = PlannerColors.of(context);
    final r = ref.watch(routineProvider);
    final eff = ref.watch(effectiveTasksProvider);
    final today = ref.watch(todayProvider);
    final now = ref.watch(nowMinuteProvider);
    final st = ref.watch(stagingProvider);
    final deadlines = ref.watch(deadlinesProvider);
    final weekendCap = ref.watch(historyDaysProvider);
    final act = ref.read(actionsProvider);
    final drag = _drag;
    final dragP = drag == null
        ? eff
        : ripple(eff, drag.id, drag.day, drag.start, r);
    final ms = PlannerMotion.ms;
    final dark = c.isDark;

    // The day's "next" task (full colour), as on Today.
    Task? cur, next;
    for (final t in stableSorted(
      dragP.where((t) => t.day == today && t.isLive),
      (a, b) => a.start! - b.start!,
    )) {
      if (!t.done && now >= t.start! && now < t.end!) cur ??= t;
    }
    for (final t in stableSorted(
      dragP.where((t) => t.day == today && t.isLive),
      (a, b) => a.start! - b.start!,
    )) {
      if (!t.done && t.start! >= now && t.id != cur?.id) {
        next = t;
        break;
      }
    }

    return LayoutBuilder(
      builder: (context, box) {
        final g = BoardGeo(
          width: box.maxWidth,
          week: widget.week,
          sel: widget.sel,
          start: weekStart(widget.sel),
          allExpanded: widget.allExpanded,
        );
        final children = <Widget>[];
        Widget pos(
          Key key,
          double x,
          double y,
          double w,
          double h,
          Widget child, {
          int msDur = 560,
          Curve curve = PlannerMotion.boardCurve,
        }) => AnimatedPositioned(
          key: key,
          duration: ms(context, msDur),
          curve: curve,
          left: x,
          top: y,
          width: math.max(0, w),
          height: math.max(0, h),
          child: child,
        );

        // Axis every 3h.
        for (final m in const [360, 540, 720, 900, 1080, 1260, 1440]) {
          children.add(
            Positioned(
              left: 0,
              top: g.yOf(m) - 6,
              width: 22,
              child: ExcludeSemantics(
                child: Text(
                  m == 1440 ? '24' : fmt(m).substring(0, 2),
                  style: PlannerType.time(size: 10, weight: 500, color: c.t3),
                ),
              ),
            ),
          );
        }

        // Columns with header and load bar.
        for (var i = 0; i < 7; i++) {
          final d = g.start + i;
          final exp = g.isExpanded(d);
          final cap = capOf(
            d,
            r,
            dragP,
            0,
            weekendCap: learnedWeekendCap(d, dragP, historyDays: weekendCap),
          );
          final tot = cap.planned + cap.done;
          final over = tot - cap.realistic;
          final isOver = over > 15;
          final w = g.ws[i];
          final bw = math.max(4.0, w - (exp ? 8 : 6));
          final sc = math.max(math.max(tot, cap.realistic), 1);
          final past = d < today;
          final hover = drag != null && drag.day == d;
          final hc = d == today ? c.tx : c.t2;
          final capText = isOver
              ? '+${dur(over)}'
              : '${dur(tot)} / ${dur(cap.realistic)}';
          children.add(
            pos(
              ValueKey('col$i'),
              g.xs[i],
              0,
              w,
              g.height - 8,
              Semantics(
                button: true,
                selected: exp,
                label:
                    '${dayLabel(d)}. ${dur(tot)} planned of ${dur(cap.realistic)} realistic.${isOver ? ' Over by ${dur(over)}.' : ''}',
                onTap: () => act.selDay(d),
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => act.selDay(d),
                  child: AnimatedContainer(
                    duration: ms(context, 300),
                    decoration: BoxDecoration(
                      color: exp && !widget.allExpanded || hover
                          ? c.s1
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Opacity(
                      opacity: past ? 0.62 : 1,
                      child: Stack(
                        clipBehavior: Clip.hardEdge,
                        children: [
                          // Compact header (letter + date) in Week mode.
                          Positioned(
                            left: 0,
                            right: 0,
                            top: 4,
                            child: AnimatedOpacity(
                              opacity: !exp && g.collapsed >= 20 ? 1 : 0,
                              duration: ms(context, 300),
                              child: Column(
                                children: [
                                  Text(
                                    dayLetters[weekday0(d)],
                                    style: PlannerType.time(
                                      size: 10,
                                      weight: 500,
                                      color: c.t3,
                                    ),
                                  ),
                                  Text(
                                    '${dayNumber(d)}',
                                    style: PlannerType.ui(
                                      13,
                                      weight: d == today ? 600 : 500,
                                      color: hc,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // Sliver letter in the day zooms.
                          Positioned(
                            left: 0,
                            right: 0,
                            top: 8,
                            child: AnimatedOpacity(
                              opacity: !exp && g.collapsed < 20 ? 1 : 0,
                              duration: ms(context, 300),
                              child: Text(
                                dayLetters[weekday0(d)],
                                textAlign: TextAlign.center,
                                style: PlannerType.time(
                                  size: 9,
                                  weight: 500,
                                  color: hc,
                                ),
                              ),
                            ),
                          ),
                          // Expanded header: "Tue 29" and the load.
                          if (w > 48)
                            Positioned(
                              left: 8,
                              right: 8,
                              top: 6,
                              child: AnimatedOpacity(
                                opacity: exp ? 1 : 0,
                                duration: ms(context, 300),
                                // Hidden while a zoom squeezes the column.
                                child: LayoutBuilder(
                                  builder: (context, bx) => bx.maxWidth < 120
                                      ? const SizedBox(height: 18)
                                      : Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.baseline,
                                          textBaseline: TextBaseline.alphabetic,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                dayShort(d),
                                                maxLines: 1,
                                                overflow: TextOverflow.clip,
                                                style: PlannerType.bricolage600(
                                                  14,
                                                  color: hc,
                                                ),
                                              ),
                                            ),
                                    const SizedBox(width: 4),
                                            Text(
                                              capText,
                                              maxLines: 1,
                                              style: PlannerType.time(
                                                size: 10.5,
                                                weight: 500,
                                                color: isOver ? c.tx : c.t3,
                                              ),
                                            ),
                                          ],
                                        ),
                                ),
                              ),
                            ),
                          // Load bar: fill tx to realistic, stripes past it.
                          AnimatedPositioned(
                            duration: ms(context, 560),
                            curve: PlannerMotion.boardCurve,
                            top: 36,
                            left: exp ? 4 : (w - bw) / 2,
                            width: bw,
                            height: 3,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(1),
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: ColoredBox(color: c.ln),
                                  ),
                                  AnimatedPositioned(
                                    duration: ms(context, 620),
                                    curve: PlannerMotion.boardCurve,
                                    left: 0,
                                    top: 0,
                                    bottom: 0,
                                    width:
                                        math.min(tot, cap.realistic) / sc * bw,
                                    child: ColoredBox(color: c.tx),
                                  ),
                                  AnimatedPositioned(
                                    duration: ms(context, 620),
                                    curve: PlannerMotion.boardCurve,
                                    left: cap.realistic / sc * bw,
                                    top: 0,
                                    bottom: 0,
                                    width: math.max(0, over) / sc * bw,
                                    child: CustomPaint(
                                      painter: HatchPainter(
                                        color: c.tx,
                                        width: 1.5,
                                        period: 3.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (d == today)
                            Positioned(
                              top: 30,
                              left: w / 2 - 2,
                              width: 4,
                              height: 2,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: c.tx,
                                  borderRadius: BorderRadius.circular(1),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        // Commitment bands and protected hatch.
        for (var i = 0; i < 7; i++) {
          final d = g.start + i;
          final exp = g.isExpanded(d);
          for (final x in baseItems(d, r)) {
            if (x.kind == ItemKind.marker || x.end <= 360) continue;
            final y = g.yOf(x.start);
            final h = math.max(2.0, g.yOf(x.end) - y - 1);
            final fixed = x.kind == ItemKind.fixed;
            children.add(
              pos(
                ValueKey('band$i-${x.id}'),
                g.xs[i],
                y,
                g.ws[i],
                h,
                IgnorePointer(
                  child: Opacity(
                    opacity: d < today ? 0.62 : 1,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: fixed
                                ? ColoredBox(
                                    color: (x.cat ?? Category.work).tintAt(
                                      c,
                                      dark ? 0.30 : 0.24,
                                    ),
                                  )
                                : CustomPaint(
                                    painter: HatchPainter(
                                      color: c.ln,
                                      period: 5,
                                    ),
                                  ),
                          ),
                          if (exp && h >= 16)
                            Positioned(
                              left: 8,
                              top: 4,
                              right: 6,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    x.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.clip,
                                    style: PlannerType.ui(11.5, color: c.t2),
                                  ),
                                  if (h >= 30)
                                    Text(
                                      '${fmt(x.start)} → ${fmt(x.end)}',
                                      maxLines: 1,
                                      style: PlannerType.time(
                                        size: 10,
                                        color: c.t3,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }
        }

        // Free gaps of 40 min or more in the expanded day.
        final selLayout = buildDay(widget.sel, r, dragP);
        if (!widget.allExpanded && g.contains(widget.sel)) {
          for (final gp in selLayout.gaps) {
            if (gp.end <= 360 || gp.end - gp.start < 40) continue;
            if (widget.sel == today && gp.end <= now) continue;
            final a = widget.sel == today
                ? math.max(gp.start, ceil5(now))
                : gp.start;
            final y = g.yOf(a);
            final h = g.yOf(gp.end) - y - 2;
            if (h <= 8) continue;
            children.add(
              pos(
                ValueKey('gap-${gp.id}'),
                g.x(widget.sel) + 3,
                y,
                g.w(widget.sel) - 6,
                h,
                IgnorePointer(
                  child: DashedBox(
                    color: c.ln,
                    radius: 3,
                    child: Align(
                      alignment: Alignment.bottomRight,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(0, 0, 6, 3),
                        child: h >= 18
                            ? Text(
                                '${dur(gp.end - a)} free',
                                style: PlannerType.time(size: 10, color: c.t3),
                              )
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }
        }

        // Deadline rules.
        for (final dl in deadlines) {
          if (!g.contains(dl.day)) continue;
          final exp = g.isExpanded(dl.day);
          final y = g.yOf(dl.minute ?? 1080) - 1;
          children.add(
            pos(
              ValueKey('dl-${dl.id}'),
              g.x(dl.day),
              y,
              g.w(dl.day),
              2,
              IgnorePointer(
                child: Semantics(
                  label: 'Due ${fmt(dl.minute ?? 1080)}, ${dl.title}',
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(child: ColoredBox(color: c.tx)),
                      if (exp)
                        Positioned(
                          right: 4,
                          bottom: 3,
                          child: Text(
                            'Due ${fmt(dl.minute ?? 1080)}, ${dl.title}',
                            style: PlannerType.time(
                              size: 10,
                              weight: 500,
                              color: c.tx,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        // Tasks: blocks in expanded days, 4px transit lines elsewhere.
        for (final t0 in eff) {
          final t = dragP.firstWhere((x) => x.id == t0.id, orElse: () => t0);
          if (!t.isLive || !g.contains(t.day!)) continue;
          final d = t.day!;
          final exp = g.isExpanded(d);
          final missed =
              !t.done && (d < today || (d == today && t.end! <= now));
          final isN = cur?.id == t.id;
          final nx = next?.id == t.id;
          final fullC = t.done || isN || nx;
          final isDrag = drag?.id == t.id;
          var x = g.x(d), w = g.w(d);
          var y = g.yOf(t.start!);
          var h = math.max(3.0, g.yOf(t.end!) - y - 1);
          if (exp) {
            x += 3;
            w -= 6;
          } else {
            final lw = widget.week ? 4.0 : 3.0;
            x = x + w / 2 - lw / 2;
            w = lw;
          }
          if (isDrag) {
            final o = drag!.origin;
            final oy = g.yOf(o.start!);
            x = g.x(o.day!) + 3 + drag.dx;
            w = g.w(o.day!) - 6;
            y = oy + drag.dy;
            h = math.max(3.0, g.yOf(o.end!) - oy - 1);
          }
          final col = t.cat.color;
          final bg = missed
              ? Colors.transparent
              : fullC
              ? col
              : exp || isDrag
              ? t.cat.tintAt(c, dark ? 0.28 : 0.22)
              : c.mix(col, 0.55);
          final showText = (exp || isDrag) && h >= 13;
          final titleC = fullC && !missed
              ? t.cat.ink
              : missed
              ? c.t2
              : c.tx;
          final subC = fullC && !missed
              ? t.cat.ink.withValues(alpha: 0.75)
              : c.t3;
          final fresh = st.fresh.containsKey(t.id);
          final interactive = exp || isDrag;
          Widget block = AnimatedContainer(
            duration: ms(context, 300),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(exp || isDrag ? 3 : 2),
              boxShadow: fresh
                  ? [BoxShadow(color: col, spreadRadius: 2)]
                  : null,
            ),
            foregroundDecoration: isDrag
                ? BoxDecoration(
                    border: Border.all(color: c.tx, width: 1.5),
                    borderRadius: BorderRadius.circular(3),
                  )
                : null,
            clipBehavior: Clip.hardEdge,
            child: Stack(
              children: [
                if (missed)
                  Positioned.fill(child: DashedBox(color: c.t3, radius: 3)),
                if (showText)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(7, 3, 4, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${t.title}${t.recurrence != null ? ' ↻' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PlannerType.taskTitle(size: 12, color: titleC),
                        ),
                        if (h >= 30)
                          Text(
                            '${fmt(t.start!)} → ${fmt(t.end!)}',
                            maxLines: 1,
                            style: PlannerType.time(size: 10, color: subC),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          );
          block = AnimatedScale(
            scale: isDrag ? 1.03 : 1,
            duration: PlannerMotion.of(context, PlannerMotion.snap),
            curve: PlannerMotion.snapCurve,
            child: block,
          );
          if (interactive) {
            block = TaskFocus(
              taskId: t.id,
              radius: 2,
              child: _BlockGestures(
                onTap: () => act.openBlock(t.id),
                onStart: () => _begin(t),
                onMove: (delta, global) => _move(g, delta, global, r, today, now),
                onEnd: _end,
                child: block,
              ),
            );
          }
          final label =
              '${t.title}, ${dayLongNames[weekday0(d)]} ${fmt(t.start!)} to ${fmt(t.end!)}${t.done
                  ? ', done'
                  : missed
                  ? ', missed'
                  : ''}. Drag to move, or open.';
          block = Semantics(
            container: true,
            button: true,
            label: label,
            onTap: () => act.openBlock(t.id),
            customSemanticsActions: t.done
                ? null
                : {
                    const CustomSemanticsAction(
                      label: 'Move 15 minutes earlier',
                    ): () =>
                        act.dropOnBoard(t.id, d, t.start! - 15),
                    const CustomSemanticsAction(
                      label: 'Move 15 minutes later',
                    ): () =>
                        act.dropOnBoard(t.id, d, t.start! + 15),
                    const CustomSemanticsAction(
                      label: 'Move to the next day',
                    ): () =>
                        act.dropOnBoard(t.id, d + 1, t.start!),
                    if (d > today)
                      const CustomSemanticsAction(
                        label: 'Move to the previous day',
                      ): () =>
                          act.dropOnBoard(t.id, d - 1, t.start!),
                  },
            excludeSemantics: true,
            child: IgnorePointer(ignoring: !interactive, child: block),
          );
          children.add(
            AnimatedPositioned(
              key: ValueKey('t-${t.id}'),
              duration: isDrag ? Duration.zero : ms(context, 560),
              curve: PlannerMotion.boardCurve,
              left: x,
              top: y,
              width: math.max(0, w),
              height: h,
              child: block,
            ),
          );
        }

        // Drag ghost with its readout.
        if (drag != null) {
          final p = dragP.firstWhere((x) => x.id == drag.id);
          final gy = g.yOf(p.start!);
          final gh = math.max(4.0, g.yOf(p.end!) - gy - 1);
          children.add(
            Positioned(
              left: g.x(p.day!) + 3,
              top: gy,
              width: g.w(p.day!) - 6,
              height: gh,
              child: IgnorePointer(
                child: DashedBox(
                  color: p.cat.color,
                  radius: 3,
                  strokeWidth: 1.5,
                ),
              ),
            ),
          );
          children.add(
            Positioned(
              left: math.min(g.x(p.day!), box.maxWidth - 130),
              top: math.max(0, gy - 22),
              height: 18,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.tx,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${dayShort(p.day!)} ${fmt(p.start!)} → ${fmt(p.end!)}',
                    style: PlannerType.time(size: 10, weight: 600, color: c.bg),
                  ),
                ),
              ),
            ),
          );
        }

        // Now line in today's column.
        if (g.contains(today) && now >= 360) {
          children.add(
            pos(
              const ValueKey('nowline'),
              g.x(today),
              g.yOf(now),
              g.w(today),
              1.5,
              IgnorePointer(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(child: ColoredBox(color: c.tx)),
                    Positioned(
                      left: -3,
                      top: -3,
                      width: 7,
                      height: 7,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: c.tx,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        // Scan lines after a move.
        for (final d in st.recalcDays.toSet()) {
          if (!g.contains(d)) continue;
          children.add(
            Positioned(
              key: ValueKey('scan-${st.recalcKey}-$d'),
              left: g.x(d),
              width: g.w(d),
              top: BoardGeo.hb,
              height: BoardGeo.bh,
              child: const IgnorePointer(child: _ColumnScan()),
            ),
          );
        }

        final empty =
            widget.showEmpty && !eff.any((t) => t.isLive && g.contains(t.day!));
        if (empty) {
          children.add(
            Positioned(
              left: 40,
              right: 14,
              top: 180,
              child: IgnorePointer(
                child: Column(
                  children: [
                    Text(
                      'Your week is clear.',
                      style: PlannerType.bricolage600(20, color: c.tx),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Tell Planner what you want to accomplish, and it will find the time.',
                      textAlign: TextAlign.center,
                      style: PlannerType.body(
                        size: 13,
                        color: c.t2,
                      ).copyWith(height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return SizedBox(
          key: _key,
          height: g.height,
          child: Stack(clipBehavior: Clip.none, children: children),
        );
      },
    );
  }
}

/// Tap to open; long press 250ms on touch (or a mouse drag) to move.
class _BlockGestures extends StatelessWidget {
  const _BlockGestures({
    required this.onTap,
    required this.onStart,
    required this.onMove,
    required this.onEnd,
    required this.child,
  });
  final VoidCallback onTap, onStart, onEnd;
  final void Function(Offset delta, Offset global) onMove;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: {
          TapGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                TapGestureRecognizer.new,
                (r) => r.onTap = onTap,
              ),
          LongPressGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
                () => LongPressGestureRecognizer(
                  duration: const Duration(milliseconds: 250),
                  supportedDevices: const {
                    PointerDeviceKind.touch,
                    PointerDeviceKind.stylus,
                    PointerDeviceKind.invertedStylus,
                  },
                ),
                (r) => r
                  ..onLongPressStart = ((_) => onStart())
                  ..onLongPressMoveUpdate = ((d) =>
                      onMove(d.offsetFromOrigin, d.globalPosition))
                  ..onLongPressEnd = ((_) => onEnd())
                  ..onLongPressCancel = onEnd,
              ),
          PanGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<PanGestureRecognizer>(
                () => PanGestureRecognizer(
                  supportedDevices: const {
                    PointerDeviceKind.mouse,
                    PointerDeviceKind.trackpad,
                  },
                ),
                (r) {
                  var origin = Offset.zero;
                  r
                    ..onStart = ((d) {
                      origin = d.globalPosition;
                      onStart();
                    })
                    ..onUpdate = ((d) =>
                        onMove(d.globalPosition - origin, d.globalPosition))
                    ..onEnd = ((_) => onEnd())
                    ..onCancel = onEnd;
                },
              ),
        },
        child: child,
      ),
    );
  }
}

/// A 2px tx line running down a column (700ms), fading in and out.
class _ColumnScan extends StatefulWidget {
  const _ColumnScan();
  @override
  State<_ColumnScan> createState() => _ColumnScanState();
}

class _ColumnScanState extends State<_ColumnScan>
    with SingleTickerProviderStateMixin {
  late final AnimationController _a;

  @override
  void initState() {
    super.initState();
    _a = AnimationController(vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _a
        ..duration = PlannerMotion.ms(context, 700)
        ..forward();
    });
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = PlannerColors.of(context);
    return LayoutBuilder(
      builder: (context, box) => AnimatedBuilder(
        animation: _a,
        builder: (context, _) {
          final v = const Cubic(0.4, 0, 0.2, 1).transform(_a.value);
          final o = _a.value < 0.12
              ? _a.value / 0.12
              : _a.value > 0.88
              ? (1 - _a.value) / 0.12
              : 1.0;
          return Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: v * (box.maxHeight - 2),
                height: 2,
                child: Opacity(
                  opacity: _a.isCompleted ? 0 : o.clamp(0, 1),
                  child: ColoredBox(color: c.tx),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
