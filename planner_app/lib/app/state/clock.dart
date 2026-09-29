import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/time.dart';

/// The app clock (README 10, `clockProvider`): ticks every second. In debug
/// it can be pinned to a virtual time and sped up (the prototype's "Clock
/// +30 min" and 60× controls) so journeys can be checked by eye.
class ClockController extends Notifier<DateTime> {
  Timer? _timer;
  DateTime? _virtualStart;
  DateTime? _realStart;
  double _speed = 1;

  /// Real time source; tests can swap it.
  static DateTime Function() realNow = DateTime.now;

  @override
  DateTime build() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => state = _now());
    ref.onDispose(() => _timer?.cancel());
    return _now();
  }

  DateTime _now() {
    final real = realNow();
    if (_virtualStart == null) return real;
    final elapsed = real.difference(_realStart!);
    return _virtualStart!.add(elapsed * _speed);
  }

  bool get isVirtual => _virtualStart != null;
  double get speed => _speed;

  /// Pins the clock to [at], running at [speed]×.
  void pin(DateTime at, {double speed = 1}) {
    _virtualStart = at;
    _realStart = realNow();
    _speed = speed;
    state = _now();
  }

  void setSpeed(double speed) {
    final now = _now();
    _virtualStart = now;
    _realStart = realNow();
    _speed = speed;
    state = now;
  }

  void advance(Duration d) {
    final now = _now().add(d);
    _virtualStart = now;
    _realStart = realNow();
    state = now;
  }

  void useRealTime() {
    _virtualStart = null;
    _realStart = null;
    _speed = 1;
    state = _now();
  }
}

final clockProvider = NotifierProvider<ClockController, DateTime>(ClockController.new);

/// Today's epoch day. Only notifies when the day changes.
final todayProvider = Provider<int>((ref) => dayOf(ref.watch(clockProvider)));

/// Minutes since midnight including seconds (the now-line moves each second).
final nowProvider = Provider<double>((ref) => minuteOf(ref.watch(clockProvider)));

/// Whole minutes since midnight: capacity and layout rebuild once a minute.
final nowMinuteProvider = Provider<int>((ref) => ref.watch(nowProvider).floor());
