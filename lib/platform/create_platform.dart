/// `createPlatform()`: the real [KartkaPlatform] for this build target.
///
/// Android gets `io/`, the web build (desktop Chrome app) gets `web/`.
library;

import 'package:kartka/platform/platform.dart' show KartkaPlatform;

export 'io/create_platform_io.dart'
    if (dart.library.js_interop) 'web/create_platform_web.dart';
