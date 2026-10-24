/// Android / VM: the app window is already full screen; nothing to toggle.
Future<void> setBrowserFullscreen({required bool on}) async {}

/// Always `false` outside a browser.
bool get browserFullscreen => false;
