import 'dart:async';

import 'quickjs_preload_stub.dart'
    if (dart.library.io) 'quickjs_preload_io.dart';

/// Preloads flutter_js's bundled Linux QuickJS library so engine tests run
/// under plain `flutter test` (no `LIBQUICKJSC_TEST_PATH` needed).
///
/// flutter_js later opens the same library by its soname
/// (`libquickjs_c_bridge_plugin.so`), which the dynamic loader satisfies from
/// the copy loaded here.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  preloadQuickJs();
  await testMain();
}
