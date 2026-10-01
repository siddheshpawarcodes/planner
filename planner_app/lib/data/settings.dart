import 'alarm_prefs.dart';

export 'alarm_prefs.dart';

/// App preferences (Settings, README 6.10). Stored as JSON in the key-value
/// table and included in the Drive snapshot.
enum ThemeChoice { system, dark, light }

enum MotionChoice { system, reduced, full }

enum TodayView { strip, dial }

class Settings {
  const Settings({
    this.theme = ThemeChoice.system,
    this.motion = MotionChoice.system,
    this.todayView = TodayView.strip,
    this.notifyNext = true,
    this.notifyMissed = true,
    this.notifyReview = true,
    this.taskAlarms = true,
    this.wakeWord = true,
    this.language = 'English (UK)',
    this.autoBackup = true,
    this.weekStartsMonday = true,
    this.countSkippedAsMissed = false,
    this.alarm = const AlarmPrefs(),
  });

  final ThemeChoice theme;
  final MotionChoice motion;
  final TodayView todayView;
  final bool notifyNext, notifyMissed, notifyReview;

  /// An alarm that rings at each task's start (cancelled when it's done).
  final bool taskAlarms;
  final bool wakeWord;
  final String language;
  final bool autoBackup;
  final bool weekStartsMonday;
  final bool countSkippedAsMissed;

  /// Alarm style, look, sound and actions.
  final AlarmPrefs alarm;

  /// null = follow the system.
  bool? get reducedMotion => switch (motion) {
        MotionChoice.system => null,
        MotionChoice.reduced => true,
        MotionChoice.full => false,
      };

  Settings copyWith({
    ThemeChoice? theme,
    MotionChoice? motion,
    TodayView? todayView,
    bool? notifyNext,
    bool? notifyMissed,
    bool? notifyReview,
    bool? taskAlarms,
    bool? wakeWord,
    String? language,
    bool? autoBackup,
    bool? weekStartsMonday,
    bool? countSkippedAsMissed,
    AlarmPrefs? alarm,
  }) =>
      Settings(
        theme: theme ?? this.theme,
        motion: motion ?? this.motion,
        todayView: todayView ?? this.todayView,
        notifyNext: notifyNext ?? this.notifyNext,
        notifyMissed: notifyMissed ?? this.notifyMissed,
        notifyReview: notifyReview ?? this.notifyReview,
        taskAlarms: taskAlarms ?? this.taskAlarms,
        wakeWord: wakeWord ?? this.wakeWord,
        language: language ?? this.language,
        autoBackup: autoBackup ?? this.autoBackup,
        weekStartsMonday: weekStartsMonday ?? this.weekStartsMonday,
        countSkippedAsMissed: countSkippedAsMissed ?? this.countSkippedAsMissed,
        alarm: alarm ?? this.alarm,
      );

  Map<String, Object?> toJson() => {
        'theme': theme.name,
        'motion': motion.name,
        'todayView': todayView.name,
        'notifyNext': notifyNext,
        'notifyMissed': notifyMissed,
        'notifyReview': notifyReview,
        'taskAlarms': taskAlarms,
        'wakeWord': wakeWord,
        'language': language,
        'autoBackup': autoBackup,
        'weekStartsMonday': weekStartsMonday,
        'countSkippedAsMissed': countSkippedAsMissed,
        'alarm': alarm.toJson(),
      };

  static T _enum<T extends Enum>(List<T> values, Object? name, T fallback) =>
      values.firstWhere((v) => v.name == name, orElse: () => fallback);

  static Settings fromJson(Map<String, Object?> j) => Settings(
        theme: _enum(ThemeChoice.values, j['theme'], ThemeChoice.system),
        motion: _enum(MotionChoice.values, j['motion'], MotionChoice.system),
        todayView: _enum(TodayView.values, j['todayView'], TodayView.strip),
        notifyNext: j['notifyNext'] as bool? ?? true,
        notifyMissed: j['notifyMissed'] as bool? ?? true,
        notifyReview: j['notifyReview'] as bool? ?? true,
        taskAlarms: j['taskAlarms'] as bool? ?? true,
        wakeWord: j['wakeWord'] as bool? ?? true,
        language: j['language'] as String? ?? 'English (UK)',
        autoBackup: j['autoBackup'] as bool? ?? true,
        weekStartsMonday: j['weekStartsMonday'] as bool? ?? true,
        countSkippedAsMissed: j['countSkippedAsMissed'] as bool? ?? false,
        alarm: AlarmPrefs.fromJson((j['alarm'] as Map?)?.cast<String, Object?>()),
      );
}
