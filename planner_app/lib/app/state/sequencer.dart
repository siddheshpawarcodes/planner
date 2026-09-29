import 'dart:async';

import 'package:flutter/foundation.dart';

/// Cancellable timers for choreography (prototype `at` / `clearTimers`).
/// Sequences only ever *explain* committed state; cancelling one never
/// leaves data half-written.
class Sequencer {
  final _timers = <Timer>[];

  void at(num ms, VoidCallback f) {
    late Timer t;
    t = Timer(Duration(microseconds: (ms * 1000).round()), () {
      _timers.remove(t);
      f();
    });
    _timers.add(t);
  }

  void clear() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
  }

  bool get busy => _timers.isNotEmpty;
}
