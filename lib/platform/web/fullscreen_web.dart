// coverage:ignore-file
// Browser-only DOM glue; exercised by the web build, not the VM test runner.
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Enters or leaves browser fullscreen for the whole page.
Future<void> setBrowserFullscreen({required bool on}) async {
  if (on == browserFullscreen) return;
  if (on) {
    await web.document.documentElement?.requestFullscreen().toDart;
  } else {
    await web.document.exitFullscreen().toDart;
  }
}

/// Whether the page is fullscreen now (queried live, so a browser-side Esc
/// exit is seen immediately).
bool get browserFullscreen => web.document.fullscreenElement != null;
