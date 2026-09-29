import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Loads the bundled fonts so widget tests measure text like the device.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  Future<void> load(String family, String file) async {
    final bytes = File('assets/fonts/$file').readAsBytesSync();
    final loader = FontLoader(family)..addFont(Future.value(ByteData.view(bytes.buffer)));
    await loader.load();
  }

  await load('Geist', 'Geist-Variable.ttf');
  await load('GeistMono', 'GeistMono-Variable.ttf');
  await load('Bricolage', 'BricolageGrotesque-Variable.ttf');
  await testMain();
}
