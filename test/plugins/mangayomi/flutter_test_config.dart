import 'dart:async';

import '../runtime/quickjs_preload_stub.dart'
    if (dart.library.io) '../runtime/quickjs_preload_io.dart';

/// Loads flutter_js's Linux QuickJS library (the runtime's helper), so these
/// tests run Mangayomi extensions on the Android engine under plain
/// `flutter test`.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  preloadQuickJs();
  await testMain();
}
