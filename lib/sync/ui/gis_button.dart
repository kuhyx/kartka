/// The Google Identity Services button, for the web (desktop) build.
///
/// `gisInitialize(clientId)`, `gisButton()` and `gisIdTokens()`. On web GIS
/// signs in only through its own rendered button -- the plugin's
/// `authenticate()` throws there -- so the token arrives on a stream rather
/// than as a return value. Elsewhere every call throws: Android takes the
/// plugin's account picker instead (see `google_route.dart`).
library;

export 'gis_button_stub.dart'
    if (dart.library.js_interop) 'gis_button_web.dart';
