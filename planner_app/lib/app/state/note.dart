import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One message in the NoteStrip, optionally with an action (usually Undo).
class Note {
  const Note(this.text, {this.actionLabel, this.action, required this.key});
  final String text;
  final String? actionLabel;
  final VoidCallback? action;
  final int key;
}

/// The single note strip above the nav (README 2.7). It is also the live
/// region that announces completion, placement and moves to screen readers.
class NoteController extends Notifier<Note?> {
  Timer? _timer;
  var _k = 0;

  @override
  Note? build() {
    ref.onDispose(() => _timer?.cancel());
    return null;
  }

  /// Shows [text] for 3.6s, or 5.2s when it carries an action.
  void say(String text, {String? actionLabel, VoidCallback? action}) {
    _timer?.cancel();
    state = Note(text, actionLabel: actionLabel, action: action, key: ++_k);
    _timer = Timer(Duration(milliseconds: action != null ? 5200 : 3600),
        () => state = null);
  }

  void undoable(String text, VoidCallback undo) =>
      say(text, actionLabel: 'Undo', action: undo);

  void runAction() {
    final a = state?.action;
    _timer?.cancel();
    state = null;
    a?.call();
  }

  void dismiss() {
    _timer?.cancel();
    state = null;
  }
}

final noteProvider = NotifierProvider<NoteController, Note?>(NoteController.new);
