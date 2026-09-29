import '../../domain/capacity.dart';
import '../../domain/category.dart';
import '../../domain/routine.dart';
import '../../domain/scheduler.dart';
import '../../domain/task.dart';
import '../../domain/time.dart';

/// "When?" time preference, plus an exact time when editing.
enum FormPref { any, morning, afternoon, evening, exact }

/// The TaskSheet's state (prototype `f`).
class TaskForm {
  const TaskForm({
    this.title = '',
    this.cat,
    this.catSet = false,
    this.duration,
    this.date,
    this.pref = FormPref.any,
    this.at,
    this.priority = Priority.normal,
    this.deadline,
    this.recur,
    this.editId,
    this.heard,
  });

  final String title;
  final Category? cat;

  /// The user chose the category; stop inferring it from the title.
  final bool catSet;
  final int? duration;

  /// Epoch day; null = Planner picks.
  final int? date;
  final FormPref pref;
  final int? at;
  final Priority priority;
  final int? deadline;
  final DayRule? recur;
  final String? editId;
  final String? heard;

  bool get hasTitle => title.trim().isNotEmpty;
  bool get hasDuration => duration != null;
  Category get effectiveCat => cat ?? (hasTitle ? guessCat(title) : Category.self);

  TaskForm copyWith({
    String? title,
    Object? cat = _unset,
    bool? catSet,
    Object? duration = _unset,
    Object? date = _unset,
    FormPref? pref,
    Object? at = _unset,
    Priority? priority,
    Object? deadline = _unset,
    Object? recur = _unset,
  }) =>
      TaskForm(
        title: title ?? this.title,
        cat: identical(cat, _unset) ? this.cat : cat as Category?,
        catSet: catSet ?? this.catSet,
        duration: identical(duration, _unset) ? this.duration : duration as int?,
        date: identical(date, _unset) ? this.date : date as int?,
        pref: pref ?? this.pref,
        at: identical(at, _unset) ? this.at : at as int?,
        priority: priority ?? this.priority,
        deadline: identical(deadline, _unset) ? this.deadline : deadline as int?,
        recur: identical(recur, _unset) ? this.recur : recur as DayRule?,
        editId: editId,
        heard: heard,
      );

  /// Typing a title re-infers the category unless the user picked one.
  TaskForm withTitle(String v) => copyWith(
      title: v, cat: catSet ? cat : (v.trim().isNotEmpty ? guessCat(v) : null));

  static TaskForm fromTask(Task t) => TaskForm(
        title: t.title,
        cat: t.cat,
        catSet: true,
        duration: t.end! - t.start!,
        date: t.day,
        pref: FormPref.exact,
        at: t.start,
        priority: t.priority,
        deadline: t.deadline,
        recur: t.recurrence,
        editId: t.id,
      );

  TimePref get timePref => switch (pref) {
        FormPref.morning => TimePref.morning,
        FormPref.afternoon => TimePref.afternoon,
        FormPref.evening => TimePref.evening,
        _ => TimePref.any,
      };

  /// Where Planner would place it (prototype `previewSlot`).
  DaySlot? slot(Routine r, List<Task> all, {required int today, required num now}) {
    if (!hasTitle || duration == null) return null;
    return previewSlot(duration!, r, all,
        today: today,
        now: now,
        date: date,
        pref: timePref,
        at: pref == FormPref.exact ? at : null,
        editId: editId);
  }
}

const Object _unset = Object();

/// The live preview lines: (value, sub).
(String, String) previewText(TaskForm f, DaySlot? pv, Routine r, List<Task> all,
    {required int today, required num now}) {
  if (pv == null) {
    return (
      f.hasTitle && f.hasDuration
          ? 'No room in the next 7 days'
          : f.hasTitle
              ? 'Pick a duration'
              : 'Planner will find the time',
      ''
    );
  }
  final dayName = pv.day == today
      ? 'Today'
      : pv.day == today + 1
          ? 'Tomorrow'
          : dayLongNames[weekday0(pv.day)];
  final trial = [
    for (final t in all)
      if (t.id != f.editId) t,
    Task.make('pv', f.title, f.effectiveCat, pv.day, pv.start, f.duration!),
  ];
  final c = capOf(pv.day, r, trial, pv.day == today ? now : 0);
  final sub = pv.overWindDown || c.over > 15
      ? 'This goes ${dur(c.over > 15 ? c.over : 15)} past what fits. Planner will ask before keeping it.'
      : '${dur(c.realistic - c.planned < 0 ? 0 : c.realistic - c.planned)} of realistic time left after this.';
  return ('$dayName ${fmt(pv.start)} → ${fmt(pv.end)}', sub);
}
