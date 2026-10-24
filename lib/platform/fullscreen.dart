/// Browser fullscreen for the desktop (web) build; a no-op elsewhere.
///
/// `setBrowserFullscreen({required bool on})` and `browserFullscreen`. The
/// web side reads `document.fullscreenElement` every time rather than
/// caching, so leaving fullscreen with the browser's own Esc never desyncs.
library;

export 'fullscreen_stub.dart'
    if (dart.library.js_interop) 'web/fullscreen_web.dart';
