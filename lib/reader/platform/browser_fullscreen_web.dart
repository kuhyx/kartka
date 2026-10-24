import 'dart:js_interop';

import 'package:web/web.dart' as web;

// Only compiled into the web build, which the VM test runner cannot load.
// coverage:ignore-file

/// Enters or leaves the browser's fullscreen mode for the whole page.
Future<void> setBrowserFullscreen({required bool on}) async {
  final doc = web.document;
  if (on) {
    if (doc.fullscreenElement == null) {
      await doc.documentElement?.requestFullscreen().toDart;
    }
  } else if (doc.fullscreenElement != null) {
    await doc.exitFullscreen().toDart;
  }
}
