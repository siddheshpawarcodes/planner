import '../domain/category.dart';

/// How a task alarm presents itself.
/// - [notification]: the system alarm notification (sound, repeating).
/// - [fullScreen]: Planner's own alarm screen, over the lock screen
///   (Android). Planner plays the sound itself, so it can fade in.
enum AlarmStyle { notification, fullScreen }

/// What fills the alarm screen.
enum AlarmBg { look, photo, video, category }

/// The built-in animated looks, drawn in code.
enum AlarmLookId { orb, aurora, embers, stars, sunrise, waves }

extension AlarmLookName on AlarmLookId {
  String get label => const ['Orb', 'Aurora', 'Embers', 'Stars', 'Sunrise', 'Waves'][index];
}

enum ClockFont { bricolage, geist, mono }

extension ClockFontName on ClockFont {
  String get label => const ['Bricolage', 'Geist', 'Mono'][index];
}

enum ClockSize { s, m, l, xl }

extension ClockSizeValue on ClockSize {
  String get label => const ['S', 'M', 'L', 'XL'][index];
  double get points => const [64.0, 88.0, 112.0, 140.0][index];
}

enum AlarmAlign { center, left }

/// Tints offered on the alarm screen: none, the task's category, or a
/// fixed colour (ARGB).
const alarmTints = <int>[0xFFFF7A45, 0xFFFFC94D, 0xFF4DD9A6, 0xFF4DA6FF, 0xFFA77BFF, 0xFFFF5C8A];

/// One alarm screen design: background, effects and text.
class AlarmLook {
  const AlarmLook({
    this.bg = AlarmBg.look,
    this.lookId = AlarmLookId.orb,
    this.mediaPath,
    this.blur = 0,
    this.dim = 0.25,
    this.zoom = true,
    this.tintCategory = false,
    this.tint,
    this.tintStrength = 0.3,
    this.font = ClockFont.bricolage,
    this.size = ClockSize.l,
    this.align = AlarmAlign.center,
    this.showTitle = true,
    this.showRange = true,
    this.showNext = true,
    this.message = '',
  });

  final AlarmBg bg;
  final AlarmLookId lookId;

  /// A photo, GIF or video copied into Planner's files (photo/video only).
  final String? mediaPath;

  /// Effects, 0..1: blur strength, darkening, and the tint's strength.
  final double blur, dim, tintStrength;

  /// A slow zoom across the background (Ken Burns).
  final bool zoom;

  /// Tint with the task's category colour, or with [tint] (ARGB), or none.
  final bool tintCategory;
  final int? tint;

  final ClockFont font;
  final ClockSize size;
  final AlarmAlign align;
  final bool showTitle, showRange, showNext;

  /// An optional line under the task, for example "You've got this."
  final String message;

  bool get hasTint => tintCategory || tint != null;

  AlarmLook copyWith({
    AlarmBg? bg,
    AlarmLookId? lookId,
    Object? mediaPath = _keep,
    double? blur,
    double? dim,
    bool? zoom,
    bool? tintCategory,
    Object? tint = _keep,
    double? tintStrength,
    ClockFont? font,
    ClockSize? size,
    AlarmAlign? align,
    bool? showTitle,
    bool? showRange,
    bool? showNext,
    String? message,
  }) =>
      AlarmLook(
        bg: bg ?? this.bg,
        lookId: lookId ?? this.lookId,
        mediaPath: identical(mediaPath, _keep) ? this.mediaPath : mediaPath as String?,
        blur: blur ?? this.blur,
        dim: dim ?? this.dim,
        zoom: zoom ?? this.zoom,
        tintCategory: tintCategory ?? this.tintCategory,
        tint: identical(tint, _keep) ? this.tint : tint as int?,
        tintStrength: tintStrength ?? this.tintStrength,
        font: font ?? this.font,
        size: size ?? this.size,
        align: align ?? this.align,
        showTitle: showTitle ?? this.showTitle,
        showRange: showRange ?? this.showRange,
        showNext: showNext ?? this.showNext,
        message: message ?? this.message,
      );

  Map<String, Object?> toJson() => {
        'bg': bg.name,
        'look': lookId.name,
        'media': mediaPath,
        'blur': blur,
        'dim': dim,
        'zoom': zoom,
        'tintCat': tintCategory,
        'tint': tint,
        'tintStrength': tintStrength,
        'font': font.name,
        'size': size.name,
        'align': align.name,
        'showTitle': showTitle,
        'showRange': showRange,
        'showNext': showNext,
        'message': message,
      };

  static AlarmLook fromJson(Map<String, Object?> j) => AlarmLook(
        bg: _enum(AlarmBg.values, j['bg'], AlarmBg.look),
        lookId: _enum(AlarmLookId.values, j['look'], AlarmLookId.orb),
        mediaPath: j['media'] as String?,
        blur: _unit(j['blur'], 0),
        dim: _unit(j['dim'], 0.25),
        zoom: j['zoom'] as bool? ?? true,
        tintCategory: j['tintCat'] as bool? ?? false,
        tint: (j['tint'] as num?)?.toInt(),
        tintStrength: _unit(j['tintStrength'], 0.3),
        font: _enum(ClockFont.values, j['font'], ClockFont.bricolage),
        size: _enum(ClockSize.values, j['size'], ClockSize.l),
        align: _enum(AlarmAlign.values, j['align'], AlarmAlign.center),
        showTitle: j['showTitle'] as bool? ?? true,
        showRange: j['showRange'] as bool? ?? true,
        showNext: j['showNext'] as bool? ?? true,
        message: j['message'] as String? ?? '',
      );

  @override
  bool operator ==(Object other) =>
      other is AlarmLook && _mapEq(toJson(), other.toJson());
  @override
  int get hashCode => Object.hashAll(toJson().values);
}

/// Everything about task alarms beyond on/off (Settings › Notifications).
/// Sound and actions are global; the look can differ per category.
class AlarmPrefs {
  const AlarmPrefs({
    this.style = AlarmStyle.notification,
    this.look = const AlarmLook(),
    this.overrides = const {},
    this.tonePath,
    this.toneName = 'Phone default',
    this.fadeSeconds = 0,
    this.vibrate = true,
    this.snoozeMinutes = 10,
    this.slide = false,
  });

  final AlarmStyle style;

  /// The default look, and per-category replacements.
  final AlarmLook look;
  final Map<Category, AlarmLook> overrides;

  /// A copied alarm tone in Planner's files; null = the phone's default.
  final String? tonePath;
  final String toneName;

  /// Gentle start: vibrate first, then fade the sound in over this many
  /// seconds. 0 = full volume at once.
  final int fadeSeconds;
  final bool vibrate;
  final int snoozeMinutes;

  /// Slide to confirm (Done right, Snooze left) instead of tapping, so it
  /// can't be answered by accident in a pocket.
  final bool slide;

  AlarmLook lookFor(Category c) => overrides[c] ?? look;

  AlarmPrefs copyWith({
    AlarmStyle? style,
    AlarmLook? look,
    Map<Category, AlarmLook>? overrides,
    Object? tonePath = _keep,
    String? toneName,
    int? fadeSeconds,
    bool? vibrate,
    int? snoozeMinutes,
    bool? slide,
  }) =>
      AlarmPrefs(
        style: style ?? this.style,
        look: look ?? this.look,
        overrides: overrides ?? this.overrides,
        tonePath: identical(tonePath, _keep) ? this.tonePath : tonePath as String?,
        toneName: toneName ?? this.toneName,
        fadeSeconds: fadeSeconds ?? this.fadeSeconds,
        vibrate: vibrate ?? this.vibrate,
        snoozeMinutes: snoozeMinutes ?? this.snoozeMinutes,
        slide: slide ?? this.slide,
      );

  /// Sets (or with null clears) the look for [c].
  AlarmPrefs withOverride(Category c, AlarmLook? l) {
    final m = Map.of(overrides);
    if (l == null) {
      m.remove(c);
    } else {
      m[c] = l;
    }
    return copyWith(overrides: m);
  }

  Map<String, Object?> toJson() => {
        'style': style.name,
        'look': look.toJson(),
        'overrides': {for (final e in overrides.entries) e.key.name: e.value.toJson()},
        'tonePath': tonePath,
        'toneName': toneName,
        'fade': fadeSeconds,
        'vibrate': vibrate,
        'snooze': snoozeMinutes,
        'slide': slide,
      };

  static AlarmPrefs fromJson(Map<String, Object?>? j) {
    if (j == null) return const AlarmPrefs();
    final o = (j['overrides'] as Map?)?.cast<String, Object?>() ?? const {};
    return AlarmPrefs(
      style: _enum(AlarmStyle.values, j['style'], AlarmStyle.notification),
      look: j['look'] is Map ? AlarmLook.fromJson((j['look'] as Map).cast()) : const AlarmLook(),
      overrides: {
        for (final e in o.entries)
          if (e.value is Map && Category.values.any((c) => c.name == e.key))
            categoryFromName(e.key): AlarmLook.fromJson((e.value as Map).cast()),
      },
      tonePath: j['tonePath'] as String?,
      toneName: j['toneName'] as String? ?? 'Phone default',
      fadeSeconds: (j['fade'] as num?)?.toInt() ?? 0,
      vibrate: j['vibrate'] as bool? ?? true,
      snoozeMinutes: (j['snooze'] as num?)?.toInt() ?? 10,
      slide: j['slide'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) => other is AlarmPrefs && _mapEq(toJson(), other.toJson());
  @override
  int get hashCode => Object.hash(style, look, toneName, fadeSeconds, snoozeMinutes);
}

const Object _keep = Object();

T _enum<T extends Enum>(List<T> values, Object? name, T fallback) =>
    values.firstWhere((v) => v.name == name, orElse: () => fallback);

double _unit(Object? v, double fallback) => ((v as num?)?.toDouble() ?? fallback).clamp(0.0, 1.0);

bool _mapEq(Object? a, Object? b) {
  if (a is Map && b is Map) {
    return a.length == b.length && a.keys.every((k) => b.containsKey(k) && _mapEq(a[k], b[k]));
  }
  return a == b;
}
