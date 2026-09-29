/// Time and day helpers shared by every domain function.
///
/// Days are epoch-day integers (days since 1970-01-01 on the local calendar),
/// so `weekday0(day)` gives 0 = Monday … 6 = Sunday, which matches the
/// prototype's `d % 7` convention exactly. Minutes are minutes from the
/// start of that day and may exceed 1440 for after-midnight sleep.
library;

const int minutesPerDay = 1440;

/// 1970-01-01 was a Thursday, so shift by 3 to make Monday 0.
int weekday0(int day) => (day + 3) % 7;
bool isWeekend(int day) => weekday0(day) >= 5;

/// Epoch day of a local calendar date. Uses UTC maths so DST never skews it.
int dayOf(DateTime d) =>
    DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/ 86400000;

/// Local calendar date (midnight) for an epoch day.
DateTime dateOf(int day) {
  final u = DateTime.fromMillisecondsSinceEpoch(day * 86400000, isUtc: true);
  return DateTime(u.year, u.month, u.day);
}

/// Minutes since local midnight, fractional seconds included.
double minuteOf(DateTime d) => d.hour * 60 + d.minute + d.second / 60;

/// Monday of the week containing [day].
int weekStart(int day) => day - weekday0(day);

/// The next [weekday] (0 = Monday) strictly after [today]
/// (or on [today] itself when [includeToday]).
int nextWeekday(int today, int weekday, {bool includeToday = false}) {
  var delta = (weekday - weekday0(today) + 7) % 7;
  if (delta == 0 && !includeToday) delta = 7;
  return today + delta;
}

int clampInt(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);
double clampD(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

/// Rounds up to the next 5-minute boundary (prototype `ceil5`).
int ceil5(num m) => (m / 5).ceil() * 5;

/// HH:mm, wrapping past midnight (prototype `fmt`).
String fmt(num m) {
  final v = ((m.floor() % minutesPerDay) + minutesPerDay) % minutesPerDay;
  final h = v ~/ 60, r = v % 60;
  return '${h.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}';
}

/// "3h 10m", "2h", "45m" (prototype `dur`).
String dur(num m) {
  final v = m.round() < 0 ? 0 : m.round();
  final h = v ~/ 60, r = v % 60;
  if (h > 0 && r > 0) return '${h}h ${r}m';
  if (h > 0) return '${h}h';
  return '${r}m';
}

/// Hours as a duration label (prototype `hrs`).
String hrs(double h) => dur(h * 60);

const dayShortNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const dayLongNames = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
];
const dayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
const monthLongNames = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August',
  'September', 'October', 'November', 'December'
];
const monthShortNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov',
  'Dec'
];

int dayNumber(int day) => dateOf(day).day;

/// "Wednesday 30 September"
String dayLabel(int day) {
  final d = dateOf(day);
  return '${dayLongNames[weekday0(day)]} ${d.day} ${monthLongNames[d.month - 1]}';
}

/// "Wed 30"
String dayShort(int day) => '${dayShortNames[weekday0(day)]} ${dayNumber(day)}';

/// "Wed 30 Sep"
String dayShortMonth(int day) {
  final d = dateOf(day);
  return '${dayShortNames[weekday0(day)]} ${d.day} ${monthShortNames[d.month - 1]}';
}

/// "Sat 3 Oct, 09:00" (prototype `when`).
String when(int day, int m) => '${dayShortMonth(day)}, ${fmt(m)}';

/// "28 Sep → 4 Oct" for the week containing [day].
String weekRange(int day) {
  final a = dateOf(weekStart(day)), b = dateOf(weekStart(day) + 6);
  return '${a.day} ${monthShortNames[a.month - 1]} → ${b.day} ${monthShortNames[b.month - 1]}';
}

/// Stable sort. Dart's [List.sort] is not stable and the prototype relies on
/// JavaScript's stable `Array.prototype.sort` for equal start times.
List<T> stableSorted<T>(Iterable<T> items, int Function(T a, T b) compare) {
  final indexed = items.toList().asMap().entries.toList();
  indexed.sort((a, b) {
    final c = compare(a.value, b.value);
    return c != 0 ? c : a.key - b.key;
  });
  return [for (final e in indexed) e.value];
}
