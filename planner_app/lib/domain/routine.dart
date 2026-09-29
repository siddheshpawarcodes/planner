import 'category.dart';
import 'time.dart';

enum DayRuleKind { everyDay, weekdays, weekends, weekday }

/// Which days a commitment or series applies to.
class DayRule {
  const DayRule._(this.kind, [this.weekday = 0]);
  static const everyDay = DayRule._(DayRuleKind.everyDay);
  static const weekdays = DayRule._(DayRuleKind.weekdays);
  static const weekends = DayRule._(DayRuleKind.weekends);

  /// A single weekday, 0 = Monday … 6 = Sunday.
  const DayRule.on(int weekday) : this._(DayRuleKind.weekday, weekday);

  final DayRuleKind kind;
  final int weekday;

  bool matches(int day) {
    final w = weekday0(day);
    switch (kind) {
      case DayRuleKind.everyDay:
        return true;
      case DayRuleKind.weekdays:
        return w < 5;
      case DayRuleKind.weekends:
        return w >= 5;
      case DayRuleKind.weekday:
        return w == weekday;
    }
  }

  /// "Every day", "Weekdays", "Weekends", "Every Monday".
  String get label => switch (kind) {
        DayRuleKind.everyDay => 'Every day',
        DayRuleKind.weekdays => 'Weekdays',
        DayRuleKind.weekends => 'Weekends',
        DayRuleKind.weekday => 'Every ${dayLongNames[weekday]}',
      };

  /// Plural form used in commitment rows: "Saturdays".
  String get plural => switch (kind) {
        DayRuleKind.everyDay => 'Every day',
        DayRuleKind.weekdays => 'Weekdays',
        DayRuleKind.weekends => 'Weekends',
        DayRuleKind.weekday => '${dayLongNames[weekday]}s',
      };

  String encode() =>
      kind == DayRuleKind.weekday ? 'weekday:$weekday' : kind.name;

  static DayRule decode(String s) {
    if (s.startsWith('weekday:')) return DayRule.on(int.parse(s.substring(8)));
    return switch (s) {
      'weekdays' => weekdays,
      'weekends' => weekends,
      _ => everyDay,
    };
  }

  /// Parses the labels used by the TaskSheet's Repeat chips.
  static DayRule? fromLabel(String? label) {
    if (label == null || label == 'never') return null;
    if (label == 'Every day') return everyDay;
    if (label == 'Weekdays') return weekdays;
    if (label == 'Weekends') return weekends;
    for (var i = 0; i < 7; i++) {
      if (label == 'Every ${dayLongNames[i]}') return DayRule.on(i);
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is DayRule && other.kind == kind && other.weekday == weekday;
  @override
  int get hashCode => Object.hash(kind, weekday);
  @override
  String toString() => encode();
}

class Commitment {
  const Commitment({
    required this.id,
    required this.title,
    required this.cat,
    required this.start,
    required this.end,
    required this.days,
    this.on = true,
  });

  final String id;
  final String title;
  final Category cat;
  final int start, end;
  final DayRule days;
  final bool on;

  /// "Every day, 19:00 → 20:00"
  String get label => '${days.plural}, ${fmt(start)} → ${fmt(end)}';

  Commitment copyWith({
    String? title,
    Category? cat,
    int? start,
    int? end,
    DayRule? days,
    bool? on,
  }) =>
      Commitment(
        id: id,
        title: title ?? this.title,
        cat: cat ?? this.cat,
        start: start ?? this.start,
        end: end ?? this.end,
        days: days ?? this.days,
        on: on ?? this.on,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'cat': cat.name,
        'start': start,
        'end': end,
        'days': days.encode(),
        'on': on,
      };

  static Commitment fromJson(Map<String, Object?> j) => Commitment(
        id: j['id']! as String,
        title: j['title']! as String,
        cat: categoryFromName(j['cat'] as String?),
        start: j['start']! as int,
        end: j['end']! as int,
        days: DayRule.decode(j['days']! as String),
        on: j['on'] as bool? ?? true,
      );
}

/// The onboarding defaults: Dinner on, Gym and Family call offered but off.
const defaultCommitments = [
  Commitment(
      id: 'dinner',
      title: 'Dinner',
      cat: Category.rest,
      start: 1140,
      end: 1200,
      days: DayRule.everyDay),
  Commitment(
      id: 'gym',
      title: 'Gym',
      cat: Category.body,
      start: 540,
      end: 600,
      days: DayRule.on(5),
      on: false),
  Commitment(
      id: 'call',
      title: 'Family call',
      cat: Category.people,
      start: 1080,
      end: 1110,
      days: DayRule.on(6),
      on: false),
];

class Routine {
  const Routine({
    this.wake = 420,
    this.workStart = 480,
    this.workEnd = 1140,
    this.sleep = 1440,
    this.noFixedWork = false,
    this.commitments = defaultCommitments,
  });

  /// Minutes from midnight. [sleep] can exceed 1440 for after-midnight.
  final int wake, workStart, workEnd, sleep;
  final bool noFixedWork;
  final List<Commitment> commitments;

  Routine copyWith({
    int? wake,
    int? workStart,
    int? workEnd,
    int? sleep,
    bool? noFixedWork,
    List<Commitment>? commitments,
  }) =>
      Routine(
        wake: wake ?? this.wake,
        workStart: workStart ?? this.workStart,
        workEnd: workEnd ?? this.workEnd,
        sleep: sleep ?? this.sleep,
        noFixedWork: noFixedWork ?? this.noFixedWork,
        commitments: commitments ?? this.commitments,
      );

  Map<String, Object?> toJson() => {
        'wake': wake,
        'workStart': workStart,
        'workEnd': workEnd,
        'sleep': sleep,
        'noFixedWork': noFixedWork,
        'commitments': [for (final c in commitments) c.toJson()],
      };

  static Routine fromJson(Map<String, Object?> j) => Routine(
        wake: j['wake']! as int,
        workStart: j['workStart']! as int,
        workEnd: j['workEnd']! as int,
        sleep: j['sleep']! as int,
        noFixedWork: j['noFixedWork'] as bool? ?? false,
        commitments: [
          for (final c in (j['commitments'] as List? ?? const []))
            Commitment.fromJson((c as Map).cast<String, Object?>())
        ],
      );
}
