import 'capacity.dart';
import 'category.dart';
import 'routine.dart';
import 'task.dart';
import 'time.dart';

/// The four time questions (prototype `obKey`).
enum ObField { wake, workStart, workEnd, sleep }

/// Onboarding steps: four time questions, commitments, then assembly.
const kObCommitStep = 4;
const kObBuildStep = 5;

/// The "Add your own" form (prototype `cu`).
class CustomCommitment {
  const CustomCommitment({this.title = '', this.at = 1080, this.length = 30, this.days = DayRule.everyDay});
  final String title;
  final int at, length;
  final DayRule days;

  /// Start chips and lengths offered by the form.
  static const starts = [450, 780, 1080, 1260];
  static const lengths = [30, 60];
  static const dayRules = [DayRule.everyDay, DayRule.weekdays, DayRule.weekends];

  CustomCommitment copyWith({String? title, int? at, int? length, DayRule? days}) => CustomCommitment(
        title: title ?? this.title,
        at: at ?? this.at,
        length: length ?? this.length,
        days: days ?? this.days,
      );
}

/// Onboarding answers so far (prototype `ob`). Pure: every change returns a
/// new draft, and nothing is written until "Build my rhythm".
class OnboardingDraft {
  const OnboardingDraft({
    this.step = 0,
    this.wake = 420,
    this.workStart = 480,
    this.workEnd = 1140,
    this.sleep = 1440,
    this.noWork = false,
    this.commitments = defaultCommitments,
    this.custom,
  });

  /// "Edit routine" starts from the current routine.
  factory OnboardingDraft.from(Routine r) => OnboardingDraft(
        wake: r.wake,
        workStart: r.workStart,
        workEnd: r.workEnd,
        sleep: r.sleep,
        noWork: r.noFixedWork,
        commitments: r.commitments,
      );

  final int step;
  final int wake, workStart, workEnd, sleep;
  final bool noWork;
  final List<Commitment> commitments;

  /// The open "Add your own" form, or null.
  final CustomCommitment? custom;

  /// The time being set on this step, or null (commitments, assembly).
  ObField? get field => step < 4 ? ObField.values[step] : null;
  bool get isTimeStep => step < 4;

  int valueOf(ObField f) => switch (f) {
        ObField.wake => wake,
        ObField.workStart => workStart,
        ObField.workEnd => workEnd,
        ObField.sleep => sleep,
      };

  int? get value => field == null ? null : valueOf(field!);

  /// Allowed range per question (prototype `obRange`): wake 04:00-12:00,
  /// work start after wake, work end at least 1h later, sleep up to 02:00.
  (int, int) range(ObField f) => switch (f) {
        ObField.wake => (240, 720),
        ObField.workStart => (wake + 15, 840),
        ObField.workEnd => (workStart + 60, 1380),
        ObField.sleep => (workEnd + 60 > 1200 ? workEnd + 60 : 1200, 1560),
      };

  /// Sets the current question's time, clamped, and pushes later answers
  /// forward so the day stays in order (prototype `obSet`).
  OnboardingDraft set(int v) {
    final f = field;
    if (f == null) return this;
    final (lo, hi) = range(f);
    v = clampInt(v, lo, hi);
    var w = wake, ws = workStart, we = workEnd, sl = sleep;
    switch (f) {
      case ObField.wake:
        w = v;
      case ObField.workStart:
        ws = v;
      case ObField.workEnd:
        we = v;
      case ObField.sleep:
        sl = v;
    }
    if (f == ObField.wake && ws < w + 15) ws = w + 15;
    if (we < ws + 60) we = ws + 60;
    if (sl < we + 60) sl = we + 60;
    return _copy(wake: w, workStart: ws, workEnd: we, sleep: sl);
  }

  /// −/+ 15 minutes.
  OnboardingDraft nudge(int delta) => value == null ? this : set(value! + delta);

  /// Ruler drag (2 px per minute, 5-minute snap): [dx] logical pixels from
  /// where the drag started at [from].
  OnboardingDraft drag(int from, double dx) => set(((from - dx / 2) / 5).round() * 5);

  OnboardingDraft toggleNoWork() => _copy(noWork: !noWork);

  /// Continue. "I don't work fixed hours" skips the work-end question.
  OnboardingDraft next() {
    if (step == 1 && noWork) return _copy(step: 3);
    if (step < kObBuildStep) return _copy(step: step + 1);
    return this;
  }

  OnboardingDraft back() {
    if (step == 0 || step == kObBuildStep) return this;
    return _copy(step: step == 3 && noWork ? 1 : step - 1);
  }

  bool get canBack => step > 0 && step < kObBuildStep;

  OnboardingDraft flip(String id) => _copy(commitments: [
        for (final c in commitments) c.id == id ? c.copyWith(on: !c.on) : c,
      ]);

  OnboardingDraft openCustom() => _copy(custom: const CustomCommitment());
  OnboardingDraft editCustom(CustomCommitment Function(CustomCommitment c) f) =>
      custom == null ? this : _copy(custom: f(custom!));
  OnboardingDraft cancelCustom() => OnboardingDraft(
        step: step,
        wake: wake,
        workStart: workStart,
        workEnd: workEnd,
        sleep: sleep,
        noWork: noWork,
        commitments: commitments,
      );

  /// Adds the custom commitment (switched on, category inferred from the
  /// title). A blank title does nothing.
  OnboardingDraft addCustom(String id) {
    final cu = custom;
    if (cu == null || cu.title.trim().isEmpty) return this;
    final title = cu.title.trim();
    final c = Commitment(
        id: id, title: title, cat: guessCat(title), start: cu.at, end: cu.at + cu.length, days: cu.days);
    return OnboardingDraft(
      step: step,
      wake: wake,
      workStart: workStart,
      workEnd: workEnd,
      sleep: sleep,
      noWork: noWork,
      commitments: [...commitments, c],
    );
  }

  Routine toRoutine() => Routine(
        wake: wake,
        workStart: workStart,
        workEnd: workEnd,
        sleep: sleep,
        noFixedWork: noWork,
        commitments: commitments,
      );

  /// The routine the live 24h bar draws: sleep capped at midnight.
  Routine get preview => toRoutine().copyWith(sleep: sleep < 1440 ? sleep : 1440);

  OnboardingDraft _copy({
    int? step,
    int? wake,
    int? workStart,
    int? workEnd,
    int? sleep,
    bool? noWork,
    List<Commitment>? commitments,
    CustomCommitment? custom,
  }) =>
      OnboardingDraft(
        step: step ?? this.step,
        wake: wake ?? this.wake,
        workStart: workStart ?? this.workStart,
        workEnd: workEnd ?? this.workEnd,
        sleep: sleep ?? this.sleep,
        noWork: noWork ?? this.noWork,
        commitments: commitments ?? this.commitments,
        custom: custom ?? this.custom,
      );
}

/// Question and subtitle copy per step (README 6.1).
const obQuestions = [
  'When do you wake up?',
  'When does work begin?',
  'When does work end?',
  'When do you normally sleep?',
  'What recurring commitments do you have?',
];
const obSubtitles = [
  'Your day starts here. Planner never schedules before it.',
  'Planner keeps working hours off-limits.',
  'Your own time usually starts after this.',
  'Planner protects the last 30 minutes as wind-down.',
  'Planner builds around these. Pick any that apply.',
];

/// The first weekday on or after [today]: the day the assembly builds.
int firstWeekday(int today) => weekday0(today) < 5 ? today : today + 7 - weekday0(today);

/// The first Saturday on or after [today].
int firstSaturday(int today) => today + ((5 - weekday0(today)) % 7);

/// "3h 10m of realistic time every weekday evening. Up to 6h on weekends."
String rhythmCopy(Routine r, int today) {
  final wk = capOf(firstWeekday(today), r, const <Task>[], 0).realistic;
  final we = capOf(firstSaturday(today), r, const <Task>[], 0).realistic;
  return '${dur(wk)} of realistic time every weekday evening. Up to ${dur(we)} on weekends.';
}
