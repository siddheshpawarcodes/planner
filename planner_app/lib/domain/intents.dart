import 'base_day.dart';
import 'capacity.dart';
import 'category.dart';
import 'routine.dart';
import 'scheduler.dart';
import 'series.dart';
import 'task.dart';
import 'time.dart';

// ===================================================================== parse

enum IntentKind { add, move, complete, delete, ask, planEvening, reschedule, recur, unknown }

/// A spoken task: title plus optional slots.
class SpokenTask {
  const SpokenTask(this.title, {this.duration, this.day, this.pref, this.at, this.offset});
  final String title;
  final int? duration;
  final int? day;
  final TimePref? pref;
  final int? at;

  /// "in 30 minutes", "after an hour": start this many minutes from now.
  final int? offset;
  @override
  String toString() => 'SpokenTask($title, $duration, $day, $pref, $at, +$offset)';
}

/// The parsed request (slots: title, category, duration, day, time,
/// recurrence).
class VoiceIntent {
  const VoiceIntent(
    this.kind, {
    this.tasks = const [],
    this.query,
    this.day,
    this.pref,
    this.at,
    this.rule,
    this.keywords = const {},
  });
  final IntentKind kind;
  final List<SpokenTask> tasks;

  /// Words naming an existing task ("gym").
  final String? query;
  final int? day;
  final TimePref? pref;
  final int? at;
  final DayRule? rule;

  /// Lower-case words the parser understood (the transcript highlights them).
  final Set<String> keywords;
}

const _units = {
  'zero': 0, 'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6,
  'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10, 'eleven': 11, 'twelve': 12,
  'thirteen': 13, 'fourteen': 14, 'fifteen': 15, 'sixteen': 16,
  'seventeen': 17, 'eighteen': 18, 'nineteen': 19,
};
const _tens = {'twenty': 20, 'thirty': 30, 'forty': 40, 'fifty': 50, 'sixty': 60, 'ninety': 90};
const _weekdays = [
  'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'
];

/// Lower-cases, strips punctuation and turns number words into digits.
/// Times and decimals stay whole ("3:00 p.m." is "3:00 pm", "1.5 hours"
/// keeps its point): the recogniser writes them with the same dots and
/// colons that otherwise end a phrase.
String normalizeUtterance(String s) {
  var t = s.toLowerCase().replaceAll(RegExp(r"[’']"), "'");
  t = t.replaceAllMapped(RegExp(r'(?<=\d)\s*([ap])\.\s?m\b\.?'), (m) => ' ${m[1]}m');
  t = t.replaceAll(RegExp(r'[,!?;"“”]|(?<!\d)[.:]|[.:](?!\d)'), ' ,');
  t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
  t = t.replaceAll(RegExp(r'\s+,'), ',');
  final out = <String>[];
  final words = t.split(' ');
  for (var i = 0; i < words.length; i++) {
    final raw = words[i];
    final comma = raw.endsWith(',');
    final w = comma ? raw.substring(0, raw.length - 1) : raw;
    int? n;
    var used = 0;
    final hy = w.split('-');
    if (hy.length == 2 && _tens.containsKey(hy[0]) && _units.containsKey(hy[1])) {
      n = _tens[hy[0]]! + _units[hy[1]]!;
    } else if (_tens.containsKey(w)) {
      n = _tens[w];
      final next = i + 1 < words.length ? words[i + 1].replaceAll(',', '') : '';
      if (_units.containsKey(next) && _units[next]! < 10 && _units[next]! > 0) {
        n = n! + _units[next]!;
        used = 1;
      }
    } else if (_units.containsKey(w)) {
      n = _units[w];
    }
    if (n != null) {
      final endComma = used == 1 ? words[i + 1].endsWith(',') : comma;
      out.add('$n${endComma ? ',' : ''}');
      i += used;
    } else {
      out.add(raw);
    }
  }
  var r = out.join(' ');
  r = r
      .replaceAll(RegExp(r'\b(an|a|1) (hour|hr) and a half\b'), '90 minutes')
      .replaceAll(RegExp(r'\bhalf an hour\b'), '30 minutes')
      .replaceAll(RegExp(r'\b(a )?quarter of an hour\b'), '15 minutes')
      .replaceAllMapped(RegExp(r'\b(\d+) and a half (hours|hrs)\b'), (m) => '${m[1]}.5 hours')
      .replaceAll(RegExp(r'\b(an|a) (hour|hr)\b'), '1 hour')
      // "six thirty pm", "at 6 30": a spoken time with its minutes.
      .replaceAllMapped(RegExp(r'\b(\d{1,2}) ([0-5]\d)\b(?= ?(am|pm)\b)'), (m) => '${m[1]}:${m[2]}')
      .replaceAllMapped(RegExp(r'\bat (\d{1,2}) ([0-5]\d)\b(?! ?(hours?|hrs?|h|minutes?|mins?|m)\b)'),
          (m) => 'at ${m[1]}:${m[2]}')
      .replaceAll(RegExp(r"\bo ?'? ?clock\b"), "o'clock");
  return r;
}

/// A start relative to now ("in 30 minutes", "after 1 hour from now"). Parsed
/// before durations so the number is not taken as the task's length.
final _offsetRe = RegExp(r'\b(?:in|after) (\d+(?:\.\d+)?)\s*(hours?|hrs?|h|minutes?|mins?|m)\b(?: from now)?');

int? _parseOffset(String s) {
  final m = _offsetRe.firstMatch(s);
  if (m == null) return null;
  final v = double.parse(m[1]!);
  return m[2]!.startsWith('h') ? (v * 60).round() : v.round();
}

/// The wake phrase said after tapping the orb ("Hey Planner, add gym…").
final _wakeRe = RegExp(r'^(?:(?:hey|hi|ok|okay) )?planner\b,?\s*');

/// After "Hey Planner" woke Planner, the recogniser starts while the phrase
/// is still ending and can hear its tail as a word ("…ner, add gym" came
/// out as "Hitler at gym"). For a session the wake phrase opened, this drops
/// such a leading fragment and reads a leading "at" (not before a number)
/// as the "add" it almost always was.
String stripWakeResidue(String text) {
  var s = text.trim();
  s = s.replaceFirst(
      RegExp(r'^(?:(?:hey|hi|a|the)\s+)?(?:planners?|planet|planer|banner|hitler|litter|lena|leaner|ner|nah)\b[,.]?\s*',
          caseSensitive: false),
      '');
  return s.replaceFirst(RegExp(r'^at\s+(?!\d)', caseSensitive: false), 'add ');
}

final _durRe = RegExp(r'\b(?:for )?(\d+(?:\.\d+)?)\s*(hours?|hrs?|h|minutes?|mins?|m)\b');
/// A clock time, in the ways people say one: "at 7", "at 6:30 pm",
/// "6:00 in the evening", "15:00", "for 3 pm", "around 4 o'clock".
final _timeRes = [
  RegExp(r"\bat (\d{1,2})(?:[:.](\d{2}))?\s*(am|pm|a m|p m|o'clock)?\b"),
  RegExp(r"\b(?:by |for |around |from )?(\d{1,2})[:.](\d{2})\s*(am|pm|a m|p m|o'clock)?\b"),
  RegExp(r"\b(?:by |for |around |from )?(\d{1,2})()\s*(am|pm|a m|p m|o'clock)\b"),
];

RegExpMatch? _timeMatch(String s) {
  for (final r in _timeRes) {
    final m = r.firstMatch(s);
    if (m != null) return m;
  }
  return null;
}

/// Removes every clock time from [s] (for titles and queries).
String _withoutTimes(String s) {
  var t = s;
  for (final r in _timeRes) {
    t = t.replaceAll(r, ' ');
  }
  return t;
}

int? _parseDuration(String s) {
  final m = _durRe.firstMatch(s);
  if (m == null) return null;
  final v = double.parse(m[1]!);
  final u = m[2]!;
  final mins = u.startsWith('h') ? (v * 60).round() : v.round();
  return mins < 5 ? null : mins;
}

int? _parseAt(String s) {
  final m = _timeMatch(s);
  if (m == null) return null;
  var h = int.parse(m[1]!);
  final min = (m[2] ?? '').isEmpty ? 0 : int.parse(m[2]!);
  final ap = m[3]?.replaceAll(' ', '');
  if (h > 23 || min > 59) return null;
  if (ap == 'pm' && h < 12) h += 12;
  if (ap == 'am' && h == 12) h = 0;
  if (ap != 'am' && ap != 'pm' && h <= 12) {
    // No am or pm: plans are mostly for the evening, unless it says morning.
    final morning = RegExp(r'\bmorning\b').hasMatch(s);
    if (!morning && h >= 1 && h <= 6) h += 12;
    if (!morning && h >= 7 && h <= 11 && RegExp(r'\b(evening|tonight|night)\b').hasMatch(s)) h += 12;
  }
  return h * 60 + min;
}

TimePref? _parsePref(String s) {
  if (RegExp(r'\b(morning)\b').hasMatch(s)) return TimePref.morning;
  if (RegExp(r'\b(afternoon)\b').hasMatch(s)) return TimePref.afternoon;
  if (RegExp(r'\b(evening|tonight)\b').hasMatch(s)) return TimePref.evening;
  return null;
}

int? _parseDay(String s, int today) {
  if (RegExp(r'\b(today|tonight|this evening)\b').hasMatch(s)) return today;
  if (RegExp(r'\b(tomorrow|tmrw)\b').hasMatch(s)) return today + 1;
  if (RegExp(r'\bthis weekend\b').hasMatch(s)) return weekendTarget(today);
  if (RegExp(r'\bnext week\b').hasMatch(s)) return nextWeekday(today, 0);
  for (var i = 0; i < 7; i++) {
    if (RegExp('\\b${_weekdays[i]}s?\\b').hasMatch(s)) return nextWeekday(today, i);
  }
  return null;
}

DayRule? _parseRule(String s) {
  if (RegExp(r'\b(every|each) ?day\b|\bdaily\b').hasMatch(s)) return DayRule.everyDay;
  if (RegExp(r'\b(every|each) weekday(s)?\b|\bon weekdays\b').hasMatch(s)) return DayRule.weekdays;
  if (RegExp(r'\b(every|each) weekend\b|\bon weekends\b').hasMatch(s)) return DayRule.weekends;
  for (var i = 0; i < 7; i++) {
    if (RegExp('\\b(every|each) ${_weekdays[i]}\\b|\\bon ${_weekdays[i]}s\\b').hasMatch(s)) {
      return DayRule.on(i);
    }
  }
  return null;
}

const _fillers = [
  "i'd like to", 'i would like to', 'i want to', 'i need to', 'i have to', 'i should',
  'i will', "i'll", 'remind me to', 'let me', 'please', 'can you', 'could you',
  'add', 'schedule', 'put', 'plan', 'also', 'then', 'and', 'to', 'a', 'an', 'some',
  'recurring', 'repeating', 'new', 'task', 'session', 'block', 'time for',
];
final _dayWordRe = RegExp(
    r'\b(today|tonight|tomorrow|tmrw|this evening|this weekend|next week|in the (morning|afternoon|evening)|this (morning|afternoon)|(on )?(every |each )?(monday|tuesday|wednesday|thursday|friday|saturday|sunday)s?|(every|each) ?(day|weekday|weekend)s?|daily)\b');

/// Strips filler, day, time and duration words, leaving the title.
String _titleOf(String chunk) {
  var t = chunk.replaceAll(',', ' ');
  t = _withoutTimes(t.replaceAll(_durRe, ' ')).replaceAll(_dayWordRe, ' ');
  t = t.replaceAll(RegExp(r'\bfor\b\s*$'), ' ');
  t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
  var changed = true;
  while (changed && t.isNotEmpty) {
    changed = false;
    for (final f in _fillers) {
      if (t == f || t.startsWith('$f ')) {
        t = t.substring(f.length).trim();
        changed = true;
      }
      if (t.endsWith(' $f') && (f == 'task' || f == 'session' || f == 'block' || f == 'for' || f == 'and')) {
        t = t.substring(0, t.length - f.length - 1).trim();
        changed = true;
      }
    }
    for (final end in const [' for', ' on', ' at', ' in', ' by']) {
      if (t.endsWith(end)) {
        t = t.substring(0, t.length - end.length).trim();
        changed = true;
      }
    }
  }
  return t;
}

/// Restores the speaker's capitalisation ("Flutter") and capitalises the
/// first word.
String _pretty(String lower, String original) {
  final orig = {
    for (final w in original.split(RegExp(r'[\s,.!?]+')))
      if (w.isNotEmpty) w.toLowerCase(): w
  };
  final words = lower.split(' ').where((w) => w.isNotEmpty).map((w) {
    final o = orig[w];
    return o != null && o != o.toLowerCase() && o != o.toUpperCase() ? o : w;
  }).toList();
  if (words.isEmpty) return '';
  final f = words.first;
  words[0] = f[0].toUpperCase() + f.substring(1);
  return words.join(' ');
}

const _stop = {
  'my', 'the', 'task', 'session', 'as', 'to', 'a', 'an', 'block', 'it', 'please', 'for',
  'mark', 'set', 'complete', 'completed', 'done', 'finished', 'finish', 'delete', 'remove',
  'cancel', 'drop', 'move', 'push', 'shift', 'i', 'did', 'with', 'on', 'at', 'in', 'from',
};

String? _queryOf(String s) {
  final t = _withoutTimes(s.replaceAll(_dayWordRe, ' ')).replaceAll(_durRe, ' ');
  final words = t
      .split(RegExp(r'[\s,]+'))
      .where((w) => w.isNotEmpty && !_stop.contains(w))
      .toList();
  return words.isEmpty ? null : words.join(' ');
}

Set<String> _keywordsOf(String normalized, VoiceIntent i) {
  final keep = <String>{};
  final words = normalized.split(RegExp(r'[\s,]+'));
  final titles = [for (final t in i.tasks) ...t.title.toLowerCase().split(' '), ...?i.query?.split(' ')];
  for (final w in words) {
    if (RegExp(r'^\d').hasMatch(w)) keep.add(w);
    if (RegExp(r'^(hours?|minutes?|mins?|hrs?)$').hasMatch(w)) keep.add(w);
    if (RegExp(r'^(today|tonight|tomorrow|evening|morning|afternoon|weekend|every|recurring|monday|tuesday|wednesday|thursday|friday|saturday|sunday)$')
        .hasMatch(w)) {
      keep.add(w);
    }
    if (RegExp(r'^(add|move|mark|complete|delete|remove|what|have|plan|reschedule|unfinished|learn|study|exercise)$')
        .hasMatch(w)) {
      keep.add(w);
    }
    if (titles.contains(w)) keep.add(w);
  }
  return keep;
}

/// Rule-based grammar over speech-to-text (README 6.3).
VoiceIntent parseUtterance(String utterance, {required int today}) {
  final s = normalizeUtterance(utterance).replaceFirst(_wakeRe, '');
  VoiceIntent withKeys(VoiceIntent i) => VoiceIntent(i.kind,
      tasks: i.tasks,
      query: i.query,
      day: i.day,
      pref: i.pref,
      at: i.at,
      rule: i.rule,
      keywords: _keywordsOf(s, i));

  if (s.isEmpty) return const VoiceIntent(IntentKind.unknown);

  final rule = _parseRule(s);
  if (rule != null && RegExp(r'\b(recurring|repeat|repeating|every|each|daily)\b').hasMatch(s)) {
    final title = _pretty(_titleOf(s.replaceAll(RegExp(r'\b(recurring|repeating|repeat|every|each)\b'), ' ')), utterance);
    return withKeys(VoiceIntent(IntentKind.recur,
        tasks: [SpokenTask(title.isEmpty ? 'Task' : title, duration: _parseDuration(s), at: _parseAt(s))],
        rule: rule,
        at: _parseAt(s)));
  }
  if (RegExp(r'\breschedule\b.*\b(unfinished|missed|everything|all|overdue)\b|\bmove (all )?(my )?(unfinished|missed)\b')
      .hasMatch(s)) {
    return withKeys(const VoiceIntent(IntentKind.reschedule));
  }
  if (RegExp(r'^(please )?(delete|remove|cancel|drop)\b').hasMatch(s)) {
    return withKeys(VoiceIntent(IntentKind.delete, query: _queryOf(s), day: _parseDay(s, today)));
  }
  if (RegExp(r'\b(mark|set)\b.*\b(complete|completed|done|finished)\b|^(complete|finish|finished|i finished|i did|i am done with|done with)\b')
      .hasMatch(s)) {
    return withKeys(VoiceIntent(IntentKind.complete, query: _queryOf(s)));
  }
  if (RegExp(r'^(please )?(move|push|shift|reschedule)\b').hasMatch(s)) {
    final target = s.contains(' to ') ? s.substring(s.lastIndexOf(' to ')) : s;
    return withKeys(VoiceIntent(IntentKind.move,
        query: _queryOf(s.contains(' to ') ? s.substring(0, s.lastIndexOf(' to ')) : s),
        day: _parseDay(target, today),
        pref: _parsePref(target),
        at: _parseAt(target)));
  }
  if (RegExp(r'\bplan (my |the |out )?(evening|tonight|night)\b').hasMatch(s)) {
    return withKeys(const VoiceIntent(IntentKind.planEvening));
  }
  if (RegExp(r"^(what|whats|what's|what is)\b.*\b(have|planned|on|got)\b|^(show|read|tell) (me )?(my )?(plan|day|schedule)")
      .hasMatch(s)) {
    return withKeys(VoiceIntent(IntentKind.ask, day: _parseDay(s, today) ?? today + 1));
  }

  // Add: one or more tasks in the order spoken.
  final day = _parseDay(s, today);
  final pref = _parsePref(s);
  final body = s.replaceAll(RegExp(r'\b(and )?then\b'), ',');
  final chunks = body
      .split(RegExp(r',| and (?=(?:\w+ ){0,3}\w+ for \d)| and (?=(?:learn|study|exercise|read|call|write|go|do|practice|revise|work|finish|start|walk|run)\b)'))
      .map((c) => c.trim())
      .where((c) => c.isNotEmpty)
      .toList();
  final reminder = RegExp(r'^remind me\b').hasMatch(s);
  final tasks = <SpokenTask>[];
  for (final raw in chunks) {
    final off = _parseOffset(raw);
    final c = raw.replaceAll(_offsetRe, ' ');
    final title = _pretty(_titleOf(c), utterance);
    if (title.isEmpty) continue;
    tasks.add(SpokenTask(title,
        // A reminder with no length is a short block, not an hour.
        duration: _parseDuration(c) ?? (reminder ? 15 : null),
        day: _parseDay(c, today),
        pref: _parsePref(c),
        at: _parseAt(c),
        offset: off));
  }
  final addy = RegExp(
          r"\b(add|schedule|put|remind|plan|want to|need to|have to|would like to|i'd like to|going to|gonna|i will|i'll)\b")
      .hasMatch(s);
  final slotted = tasks.any((t) => t.duration != null || t.day != null || t.at != null || t.offset != null) ||
      day != null ||
      pref != null;
  if (tasks.isEmpty || (!addy && !slotted)) {
    // Keep a time or day it did hear, so the reply can ask for the rest.
    return withKeys(VoiceIntent(IntentKind.unknown, day: day, at: _parseAt(s)));
  }
  return withKeys(VoiceIntent(IntentKind.add, tasks: tasks, day: day, pref: pref, at: _parseAt(s)));
}

// =================================================================== resolve

class VoiceRow {
  const VoiceRow(this.title, this.detail, this.cat);
  final String title, detail;
  final Category? cat;
}

enum VoiceWait { none, answer, confirm }

/// What the voice result commits, applied by the controller at SUCCESS.
sealed class VoiceEffect {
  const VoiceEffect();
}

class NoEffect extends VoiceEffect {
  const NoEffect();
}

/// New or placed tasks; the placement sequence runs for today/tomorrow.
class PlaceEffect extends VoiceEffect {
  const PlaceEffect(this.tasks, this.ids, this.day, this.firstTitle, this.firstStart);
  final List<Task> tasks;
  final List<String> ids;
  final int day;
  final String firstTitle;
  final int firstStart;
}

class MoveEffect extends VoiceEffect {
  const MoveEffect(this.task, this.toDay, this.slot);
  final Task task;
  final int toDay;
  final Slot slot;
}

class CompleteEffect extends VoiceEffect {
  const CompleteEffect(this.taskId);
  final String taskId;
}

class DeleteEffect extends VoiceEffect {
  const DeleteEffect(this.task);
  final Task task;
}

class AskEffect extends VoiceEffect {
  const AskEffect(this.day);
  final int day;
}

class RescheduleEffect extends VoiceEffect {
  const RescheduleEffect(this.tasks, this.ids);
  final List<Task> tasks;
  final List<String> ids;
}

class SeriesEffect extends VoiceEffect {
  const SeriesEffect(this.series, this.occurrences);
  final Series series;
  final List<Task> occurrences;
}

class VoiceResolution {
  const VoiceResolution({
    required this.label,
    this.rows = const [],
    this.summary = '',
    this.wait = VoiceWait.none,
    this.yes = 'Done',
    this.no,
    this.doneLabel = 'DONE',
    this.core,
    this.effect = const NoEffect(),
  });

  /// State label while the result shows ("TOMORROW EVENING").
  final String label;
  final List<VoiceRow> rows;
  final String summary;

  /// Answers and confirmations stay open; everything else commits at
  /// SUCCESS. Destructive intents always confirm.
  final VoiceWait wait;
  final String yes;
  final String? no;
  final String doneLabel;

  /// The orb's core colour at success.
  final Category? core;
  final VoiceEffect effect;
}

const _synonyms = [
  {'gym', 'exercise', 'workout', 'training', 'run', 'running'},
  {'study', 'revise', 'revision', 'studying'},
  {'read', 'reading'},
  {'call', 'phone', 'ring'},
];

bool _matches(Task t, String query) {
  final title = t.title.toLowerCase();
  for (final q in query.split(' ')) {
    if (q.length < 3) continue;
    if (title.contains(q)) return true;
    for (final g in _synonyms) {
      if (g.contains(q) && g.any(title.contains)) return true;
    }
  }
  return false;
}

String _noun(String? q) => (q == null || q.isEmpty) ? 'matching' : q.split(' ').last;

VoiceResolution _notFound(String? what, {String where = ''}) => VoiceResolution(
      label: 'NOT FOUND',
      summary:
          "There's no ${_noun(what)} task on your plan${where.isEmpty ? '' : ' $where'}. Try “Add gym tomorrow for one hour.”",
      wait: VoiceWait.answer,
    );

String _slotText(int d, Slot sl, int today) =>
    '${d == today + 1 ? 'Tomorrow' : d == today ? 'Today' : dayShort(d)}, ${fmt(sl.start)}';

/// Resolves an intent against the plan (prototype `resolve`). Pure: the
/// result describes what to commit; nothing is written here.
VoiceResolution resolveIntent(
  VoiceIntent i, {
  required List<Task> tasks,
  required Routine routine,
  required int today,
  required num now,
  required String Function() newId,
  DateTime? createdAt,
}) {
  final r = routine;
  final tom = today + 1;
  Task? findNext(String? q, {bool todayOnly = false}) {
    if (q == null) return null;
    final c = stableSorted(
        tasks.where((t) =>
            t.isLive && !t.done && _matches(t, q) && (todayOnly ? t.day == today : t.day! >= today)),
        (a, b) => a.day != b.day ? a.day! - b.day! : a.start! - b.start!);
    return c.isEmpty ? null : c.first;
  }

  switch (i.kind) {
    case IntentKind.add:
    case IntentKind.planEvening:
      final evening = i.kind == IntentKind.planEvening;
      final List<TaskSpec> specs;
      if (evening) {
        specs = [
          for (final t in tasks)
            if (t.day == null && !t.deleted)
              TaskSpec(title: t.title, cat: t.cat, duration: t.duration, day: today, existingId: t.id)
        ];
      } else {
        final defDay = i.day ?? tom;
        specs = [
          for (final t in i.tasks)
            if (t.offset != null)
              // "In 30 minutes": today (or past midnight, tomorrow) from now.
              TaskSpec(
                title: t.title,
                cat: guessCat(t.title),
                duration: t.duration ?? 60,
                day: today + ceil5(now + t.offset!) ~/ 1440,
                at: ceil5(now + t.offset!) % 1440,
              )
            else
              TaskSpec(
                title: t.title,
                cat: guessCat(t.title),
                duration: t.duration ?? 60,
                day: t.day ?? defDay,
                pref: t.pref ?? i.pref,
                at: t.at ?? (i.tasks.length == 1 ? i.at : null),
              )
        ];
      }
      final multi = !evening && specs.length > 1;
      final res = placeMany(specs, tasks, r,
          today: today,
          now: now,
          newId: newId,
          allowWindDown: multi,
          searchForward: !evening && !multi,
          capacityLimited: evening,
          createdAt: createdAt);
      if (res.placed.isEmpty) {
        return VoiceResolution(
          label: evening ? 'TONIGHT' : 'NO ROOM',
          summary: evening
              ? (res.left.isNotEmpty ? 'Tonight has no room left. Nothing was moved.' : 'Nothing is waiting to be scheduled.')
              : 'No free time found in the next week.',
          wait: VoiceWait.answer,
        );
      }
      final dayOf = res.placed.first.day;
      final requested = specs.first.day ?? tom;
      final label = evening
          ? 'TONIGHT'
          : dayOf == tom
              ? 'TOMORROW EVENING'
              : dayOf == today
                  ? 'TODAY'
                  : dayOf == requested
                      ? dayLongNames[weekday0(dayOf)].toUpperCase()
                      : 'NEXT FREE TIME';
      final rows = [
        for (final p in res.placed)
          VoiceRow(
              p.task.title,
              '${dur(p.slot.end - p.slot.start)}, ${p.day == dayOf && dayOf <= tom ? fmt(p.slot.start) : _slotText(p.day, p.slot, today)}',
              p.task.cat)
      ];
      var summary = '';
      if (!evening && !multi && dayOf != requested) {
        summary = requested == tom
            ? 'Tomorrow evening is full, so Planner found the next free hour.'
            : '${dayLongNames[weekday0(requested)]} is full, so Planner found the next free hour.';
      }
      // An asked-for time that wasn't free: say why, never move it silently.
      final asked = specs.length == 1 ? specs.first.at : null;
      if (!evening && asked != null && res.placed.first.slot.start != asked && summary.isEmpty) {
        final askedDay = specs.first.day ?? tom;
        final blocker = baseItems(askedDay, r).where((b) =>
            (b.kind == ItemKind.fixed || b.kind == ItemKind.protected) && b.start <= asked && asked < b.end);
        final why = blocker.isNotEmpty
            ? '${fmt(asked)} is during ${blocker.first.title}'
            : asked < r.wake
                ? '${fmt(asked)} is before you wake up'
                : '${fmt(asked)} is already taken';
        summary = '$why, so Planner found ${fmt(res.placed.first.slot.start)}.';
      }
      if (res.left.isNotEmpty) {
        final names = res.left.map((x) => x.title).join(', ');
        final many = res.left.length > 1;
        summary = evening
            ? "$names ${many ? "don't" : "doesn't"} fit tonight. ${many ? 'They stay' : 'It stays'} in Unscheduled."
            : "$names ${many ? "don't" : "doesn't"} fit this week.";
      }
      return VoiceResolution(
        label: label,
        rows: rows,
        summary: summary,
        doneLabel: evening
            ? 'PLANNED FOR TONIGHT'
            : dayOf == tom
                ? 'SCHEDULED FOR TOMORROW'
                : 'SCHEDULED',
        core: res.placed.first.task.cat,
        effect: PlaceEffect(res.tasks, [for (final p in res.placed) p.task.id], dayOf,
            res.placed.first.task.title, res.placed.first.slot.start),
      );

    case IntentKind.move:
      final g = findNext(i.query);
      if (g == null) return _notFound(i.query);
      final target = i.day ?? nextWeekday(today, 5);
      final pref = i.pref ?? (isWeekend(target) ? TimePref.morning : TimePref.evening);
      final sl = findSlot(target, g.end! - g.start!, r, tasks,
          exclude: g.id, pref: pref, at: i.at, after: target == today ? ceil5(now) : 0);
      if (sl == null) {
        return VoiceResolution(
            label: 'NO ROOM',
            summary: '${dayLongNames[weekday0(target)]} has no free time left.',
            wait: VoiceWait.answer);
      }
      return VoiceResolution(
        label: 'MOVE',
        rows: [
          VoiceRow(g.title,
              '${dayShort(g.day!)} ${fmt(g.start!)} → ${dayShortNames[weekday0(target)]} ${fmt(sl.start)}', g.cat)
        ],
        doneLabel: 'MOVED TO ${dayLongNames[weekday0(target)].toUpperCase()}',
        core: g.cat,
        effect: MoveEffect(g, target, sl),
      );

    case IntentKind.complete:
      final g = findNext(i.query, todayOnly: true);
      if (g == null) return _notFound(i.query, where: 'today');
      return VoiceResolution(
        label: 'COMPLETE',
        rows: [VoiceRow(g.title, '${fmt(g.start!)} → ${fmt(g.end!)}', g.cat)],
        doneLabel: 'MARKED DONE',
        core: g.cat,
        effect: CompleteEffect(g.id),
      );

    case IntentKind.delete:
      final g = findNext(i.query);
      if (g == null) return _notFound(i.query);
      return VoiceResolution(
        label: 'DELETE THIS TASK?',
        rows: [VoiceRow(g.title, '${dayShort(g.day!)} ${fmt(g.start!)}', g.cat)],
        wait: VoiceWait.confirm,
        yes: 'Delete ${g.title}',
        no: 'Keep it',
        doneLabel: 'DELETED',
        core: g.cat,
        effect: DeleteEffect(g),
      );

    case IntentKind.ask:
      final d = i.day ?? tom;
      final ts = stableSorted(tasks.where((t) => t.day == d && t.isLive), (a, b) => a.start! - b.start!);
      final c = capOf(d, r, tasks, d == today ? now : 0);
      final wk = isWorkDay(d, r);
      final name = d == tom
          ? 'TOMORROW, ${dayLongNames[weekday0(d)].toUpperCase()}'
          : d == today
              ? 'TODAY'
              : dayLabel(d).toUpperCase();
      return VoiceResolution(
        label: name,
        rows: ts.isNotEmpty
            ? [for (final t in ts) VoiceRow(t.title, '${fmt(t.start!)} → ${fmt(t.end!)}', t.cat)]
            : wk
                ? [VoiceRow('Office', '${fmt(r.workStart)} → ${fmt(r.workEnd)}', Category.work)]
                : const [],
        summary: ts.isNotEmpty
            ? '${dur(c.planned)} planned, ${dur(c.realistic)} realistic.'
            : 'Nothing planned yet. ${dur(c.realistic)} of realistic time is open.',
        wait: VoiceWait.answer,
        yes: d == tom ? 'Open tomorrow' : d == today ? 'Open today' : 'Open ${dayShortNames[weekday0(d)]}',
        no: 'Done',
        core: ts.isNotEmpty ? ts.first.cat : Category.work,
        effect: AskEffect(d),
      );

    case IntentKind.reschedule:
      final res = rescheduleUnfinished(tasks, r, today: today, now: now);
      if (res.moves.isEmpty) {
        final any = tasks.any((t) => isMissed(t, today, now));
        return VoiceResolution(
          label: any ? 'NO ROOM' : 'ALL CLEAR',
          summary: any
              ? 'There is no free time for them this week.'
              : 'Nothing is unfinished. Every past task is done or decided.',
          wait: VoiceWait.answer,
        );
      }
      return VoiceResolution(
        label: 'RESCHEDULE',
        rows: [for (final (t, d, sl) in res.moves) VoiceRow(t.title, '→ ${_slotText(d, sl, today)}', t.cat)],
        doneLabel: 'RESCHEDULED',
        core: res.moves.first.$1.cat,
        effect: RescheduleEffect(res.tasks, [for (final m in res.moves) m.$1.id]),
      );

    case IntentKind.recur:
      final spec = i.tasks.first;
      final rule = i.rule ?? DayRule.everyDay;
      var from = today + 1;
      while (!rule.matches(from)) {
        from++;
      }
      if (rule.kind == DayRuleKind.weekday && from == today) from += 7;
      final len = spec.duration ?? 60;
      final sl = findSlot(from, len, r, tasks, pref: TimePref.evening, at: i.at ?? spec.at);
      final start = sl?.start ?? 1200;
      final series = Series(
          id: 's${newId()}',
          title: spec.title,
          cat: guessCat(spec.title),
          rule: rule,
          start: start,
          end: start + len,
          from: from);
      final occ = materializeSeries(series, tasks, r,
          fromDay: from, toDay: today + kSeriesHorizonDays, createdAt: createdAt);
      final ruleUpper = rule.kind == DayRuleKind.weekday
          ? 'EVERY ${dayLongNames[rule.weekday].toUpperCase()}'
          : rule.label.toUpperCase();
      final d = dateOf(from);
      return VoiceResolution(
        label: ruleUpper,
        rows: [VoiceRow(spec.title, '${dur(len)}, ${fmt(start)} → ${fmt(start + len)}', series.cat)],
        summary:
            'Starts ${dayLongNames[weekday0(from)]} ${d.day} ${monthLongNames[d.month - 1]}. It repeats until you stop it.',
        doneLabel: 'REPEATS $ruleUpper',
        core: series.cat,
        effect: SeriesEffect(series, occ),
      );

    case IntentKind.unknown:
      final heard = [
        if (i.day != null) i.day == today ? 'today' : (i.day == today + 1 ? 'tomorrow' : dayLongNames[weekday0(i.day!)]),
        if (i.at != null) fmt(i.at!),
      ];
      return VoiceResolution(
        label: 'NOT SURE',
        summary: heard.isEmpty
            ? "Planner didn't catch a plan in that. Try “Add gym tomorrow for one hour.”"
            : 'Planner heard ${heard.join(' at ')} but not what to plan. Try “Add gym ${heard.join(' at ')}.”',
        wait: VoiceWait.answer,
      );
  }
}

/// The nine demo lines from the prototype's control panel.
const demoUtterances = [
  'Tomorrow I want to study polity for two hours, exercise for 45 minutes and learn Flutter for one hour.',
  'Add gym tomorrow for one hour.',
  'Move gym to Saturday.',
  'Mark gym complete.',
  'Delete my gym task.',
  'What do I have tomorrow?',
  'Plan my evening.',
  'Reschedule unfinished tasks.',
  'Add a recurring gym session every Monday.',
];
