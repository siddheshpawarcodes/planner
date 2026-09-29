import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/state/actions.dart';
import '../../app/state/clock.dart';
import '../../app/state/derived.dart';
import '../../app/state/note.dart';
import '../../app/state/ui_state.dart';
import '../../app/theme/planner_theme.dart';
import '../../domain/routine.dart';
import '../../domain/task.dart';
import '../../domain/time.dart';
import '../../widgets/controls.dart';
import '../../widgets/icons.dart';
import '../../widgets/planner_sheet.dart';
import 'task_form.dart';

/// Default suggestions until history exists.
const _defaultSuggestions = [
  ('Study polity', Category.study, 120),
  ('Exercise', Category.body, 45),
  ('Learn Flutter', Category.build, 60),
  ('Read', Category.self, 30),
  ('Call family', Category.people, 30),
];

/// TaskSheet (README 6.4): progressive create and edit.
class TaskSheet extends ConsumerStatefulWidget {
  const TaskSheet({super.key, required this.draft});
  final TaskDraft draft;
  @override
  ConsumerState<TaskSheet> createState() => _TaskSheetState();
}

class _TaskSheetState extends ConsumerState<TaskSheet> {
  late TaskForm f;
  late final TextEditingController _title;
  bool _catPick = false, _more = false;

  @override
  void initState() {
    super.initState();
    final d = widget.draft;
    final editing = d.editId == null ? null : ref.read(actionsProvider).data.task(d.editId!);
    f = editing != null
        ? TaskForm.fromTask(editing)
        : TaskForm(
            title: d.title,
            cat: d.cat,
            catSet: d.cat != null,
            duration: d.duration,
            date: d.date,
            heard: d.heard,
          ).withTitle(d.title);
    _title = TextEditingController(text: f.title);
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _set(TaskForm n) => setState(() => f = n);

  /// Suggestion chips from history (most frequent titles), else defaults.
  List<(String, Category, int)> _suggestions(List<Task> tasks) {
    final count = <String, (int, Category, int)>{};
    for (final t in tasks) {
      if (t.deleted || !t.isScheduled) continue;
      final c = count[t.title];
      count[t.title] = ((c?.$1 ?? 0) + 1, t.cat, t.end! - t.start!);
    }
    final hist = count.entries.where((e) => e.value.$1 > 1).toList()
      ..sort((a, b) => b.value.$1 - a.value.$1);
    final out = [for (final e in hist.take(5)) (e.key, e.value.$2, e.value.$3)];
    for (final d in _defaultSuggestions) {
      if (out.length >= 5) break;
      if (!out.any((o) => o.$1 == d.$1)) out.add(d);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final c = PlannerColors.of(context);
    final act = ref.read(actionsProvider);
    final r = ref.watch(routineProvider);
    final tasks = ref.watch(tasksProvider);
    final today = ref.watch(todayProvider);
    final now = ref.watch(nowMinuteProvider);
    final pv = f.slot(r, tasks, today: today, now: now);
    final (preview, sub) = previewText(f, pv, r, tasks, today: today, now: now);
    final cat = f.effectiveCat;

    Widget label(String t) =>
        Text(t, style: PlannerType.ui(13, color: c.t2));
    Widget chips(List<Widget> w) => Wrap(spacing: 6, runSpacing: 0, children: w);

    final w0 = weekday0(today);
    final weekend = w0 < 5 ? today + (5 - w0) : (w0 == 5 ? today + 1 : today + 6);
    final dates = [
      (null, 'Planner picks'),
      (today, 'Today'),
      (today + 1, 'Tomorrow'),
      (weekend, w0 < 5 ? 'Saturday' : 'Weekend'),
    ];
    final friday = w0 < 4 ? today + (4 - w0) : today + 3;
    final deadlines = [
      (null, 'None'),
      (today + 2, dayShort(today + 2)),
      (friday, dayShort(friday)),
      (today + 7, dayShort(today + 7)),
    ];
    final recurDay = weekday0(f.date ?? today + 1);
    final recurs = <(DayRule?, String)>[
      (null, 'Never'),
      (DayRule.everyDay, 'Every day'),
      (DayRule.weekdays, 'Weekdays'),
      (DayRule.on(recurDay), 'Every ${dayLongNames[recurDay]}'),
    ];
    final moreSum = [
      if (f.priority != Priority.normal) f.priority == Priority.high ? 'High priority' : 'Low priority',
      if (f.deadline != null) 'Due ${dayShort(f.deadline!)}',
      if (f.recur != null) f.recur!.label,
    ].join(', ');

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        height: 36,
        child: Row(children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(f.editId != null ? 'Edit task' : 'New task',
                  style: PlannerType.ui(13, color: c.t2)),
            ),
          ),
          PlannerIconButton(
            icon: PIcon.mic,
            label: 'Say it instead',
            size: 20,
            color: c.t2,
            onTap: () {
              act.closeSheet();
              ref.read(noteProvider.notifier).say('Voice arrives in milestone 7.');
            },
          ),
          const SheetClose(),
        ]),
      ),
      if (f.heard != null) ...[
        const SizedBox(height: 8),
        Text('From your voice: “${f.heard}”', style: PlannerType.ui(12.5, weight: 400, color: c.t3)),
      ],
      const SizedBox(height: 12),
      TextField(
        controller: _title,
        autofocus: f.editId == null && f.title.isEmpty,
        onChanged: (v) => _set(f.withTitle(v)),
        textCapitalization: TextCapitalization.sentences,
        style: PlannerType.bricolageW(25, 600, tracking: -0.01, color: c.tx),
        cursorColor: c.tx,
        decoration: InputDecoration(
          hintText: 'What do you need to do?',
          hintStyle: PlannerType.bricolageW(25, 600, tracking: -0.01, color: c.t3),
          border: UnderlineInputBorder(borderSide: BorderSide(color: c.ln)),
          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: c.ln)),
          focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: c.tx)),
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          isDense: true,
        ),
      ),
      if (!f.hasTitle) ...[
        const SizedBox(height: 10),
        chips([
          for (final (t, cat, d) in _suggestions(tasks))
            PlannerChip(
              label: t,
              selected: false,
              leading: CatSquare(cat.color),
              onTap: () {
                _title.text = t;
                _set(f.copyWith(title: t, cat: cat, catSet: true, duration: f.duration ?? d));
              },
            ),
        ]),
      ],
      _Reveal(
        on: f.hasTitle,
        child: Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: label('How long?')),
              Pressable(
                onTap: () => setState(() => _catPick = !_catPick),
                label: 'Category, ${cat.label}. Change',
                excludeChildSemantics: true,
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                      border: Border.all(color: c.ln), borderRadius: BorderRadius.circular(999)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    CatSquare(cat.color),
                    const SizedBox(width: 7),
                    Text(cat.label, style: PlannerType.ui(12, color: c.tx)),
                  ]),
                ),
              ),
            ]),
            if (_catPick) ...[
              const SizedBox(height: 4),
              chips([
                for (final k in Category.values)
                  PlannerChip(
                    label: k.label,
                    selected: k == cat,
                    leading: CatSquare(k.color),
                    onTap: () {
                      _set(f.copyWith(cat: k, catSet: true));
                      setState(() => _catPick = false);
                    },
                  ),
              ]),
            ],
            const SizedBox(height: 4),
            Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              for (final m in const [15, 30, 45, 60, 90, 120])
                PlannerChip(
                  label: dur(m),
                  selected: f.duration == m,
                  onTap: () => _set(f.copyWith(duration: m)),
                ),
              _Stepper(
                value: f.duration != null && ![15, 30, 45, 60, 90, 120].contains(f.duration)
                    ? dur(f.duration!)
                    : '',
                onMinus: () => _set(f.copyWith(duration: ((f.duration ?? 60) - 15).clamp(15, 360))),
                onPlus: () => _set(f.copyWith(duration: ((f.duration ?? 60) + 15).clamp(15, 360))),
              ),
            ]),
          ]),
        ),
      ),
      _Reveal(
        on: f.hasTitle && f.hasDuration,
        child: Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            label('When?'),
            const SizedBox(height: 4),
            chips([
              for (final (d, t) in dates)
                PlannerChip(label: t, selected: f.date == d, onTap: () => _set(f.copyWith(date: d))),
            ]),
            chips([
              for (final (p, t) in const [
                (FormPref.any, 'Any time'),
                (FormPref.morning, 'Morning'),
                (FormPref.afternoon, 'Afternoon'),
                (FormPref.evening, 'Evening'),
              ])
                PlannerChip(label: t, selected: f.pref == p, onTap: () => _set(f.copyWith(pref: p))),
            ]),
            if (f.pref == FormPref.exact && f.at != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Keeping it at ${fmt(f.at!)} if that still fits.',
                    style: PlannerType.ui(12.5, weight: 400, color: c.t3)),
              ),
            const SizedBox(height: 12),
            Pressable(
              onTap: () => setState(() => _more = !_more),
              label: 'More options',
              toggled: null,
              radius: 0,
              pressedScale: 0.99,
              excludeChildSemantics: true,
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                decoration: BoxDecoration(
                    border: Border.symmetric(horizontal: BorderSide(color: c.ln))),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('More options', style: PlannerType.ui(14, color: c.tx)),
                      const SizedBox(height: 2),
                      Text(moreSum.isEmpty ? 'Priority, deadline, repeat' : moreSum,
                          style: PlannerType.ui(12, weight: 400, color: c.t3)),
                    ]),
                  ),
                  AnimatedRotation(
                    turns: _more ? 0.25 : 0,
                    duration: PlannerMotion.ms(context, 300),
                    child: PlannerIcon(PIcon.chev, size: 16, color: c.t3),
                  ),
                ]),
              ),
            ),
            if (_more) ...[
              const SizedBox(height: 12),
              label('Priority'),
              chips([
                for (final (p, t) in const [
                  (Priority.low, 'Low'),
                  (Priority.normal, 'Normal'),
                  (Priority.high, 'High'),
                ])
                  PlannerChip(label: t, selected: f.priority == p, onTap: () => _set(f.copyWith(priority: p))),
              ]),
              const SizedBox(height: 8),
              label('Deadline'),
              chips([
                for (final (d, t) in deadlines)
                  PlannerChip(label: t, selected: f.deadline == d, onTap: () => _set(f.copyWith(deadline: d))),
              ]),
              const SizedBox(height: 8),
              label('Repeat'),
              chips([
                for (final (rr, t) in recurs)
                  PlannerChip(label: t, selected: f.recur == rr, onTap: () => _set(f.copyWith(recur: rr))),
              ]),
            ],
          ]),
        ),
      ),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Semantics(
            liveRegion: true,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Planner will place it', style: PlannerType.ui(12, weight: 400, color: c.t3)),
              const SizedBox(height: 3),
              Text(preview, style: PlannerType.ui(16, color: c.tx)),
              if (sub.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(sub, style: PlannerType.body(size: 12.5, color: c.t2).copyWith(height: 1.4)),
              ],
            ]),
          ),
          const SizedBox(height: 12),
          PrimaryPill(
            label: f.editId != null ? 'Save' : 'Schedule',
            height: 52,
            expand: true,
            onTap: pv == null ? null : () => act.schedule(f),
          ),
        ]),
      ),
    ]);
  }
}

/// Stages reveal as the form fills in.
class _Reveal extends StatelessWidget {
  const _Reveal({required this.on, required this.child});
  final bool on;
  final Widget child;
  @override
  Widget build(BuildContext context) => AnimatedSize(
        duration: PlannerMotion.ms(context, 420),
        curve: PlannerMotion.settleCurve,
        alignment: Alignment.topCenter,
        child: on
            ? TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: PlannerMotion.ms(context, 420),
                curve: PlannerMotion.settleCurve,
                child: child,
                builder: (context, v, child) => Opacity(
                  opacity: v,
                  child: Transform.translate(offset: Offset(0, 8 * (1 - v)), child: child),
                ),
              )
            : const SizedBox(width: double.infinity),
      );
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.value, required this.onMinus, required this.onPlus});
  final String value;
  final VoidCallback onMinus, onPlus;
  @override
  Widget build(BuildContext context) {
    final c = PlannerColors.of(context);
    Widget b(String t, String label, VoidCallback f) => Pressable(
          onTap: f,
          label: label,
          excludeChildSemantics: true,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c.ln)),
                child: Text(t, style: PlannerType.ui(15, weight: 400, color: c.t2)),
              ),
            ),
          ),
        );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      b('−', '15 minutes shorter', onMinus),
      SizedBox(
        width: 44,
        child: Text(value, textAlign: TextAlign.center, style: PlannerType.time(size: 12, weight: 500, color: c.tx)),
      ),
      b('+', '15 minutes longer', onPlus),
    ]);
  }
}
