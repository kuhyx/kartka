import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

/// Preloads flutter_js's bundled Linux QuickJS library so engine tests run
/// under plain `flutter test` (no `LIBQUICKJSC_TEST_PATH` needed).
///
/// flutter_js later opens the same library by its soname
/// (`libquickjs_c_bridge_plugin.so`), which the dynamic loader satisfies from
/// the copy loaded here.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  _preloadQuickJs();
  await testMain();
}

void _preloadQuickJs() {
  final config = File('.dart_tool/package_config.json');
  if (!config.existsSync()) return;
  final packages =
      (jsonDecode(config.readAsStringSync()) as Map)['packages'] as List;
  for (final p in packages.cast<Map<String, Object?>>()) {
    if (p['name'] != 'flutter_js') continue;
    final root = config.uri.resolve('${p['rootUri']}/');
    final lib = File.fromUri(
      root.resolve('linux/shared/libquickjs_c_bridge_plugin.so'),
    );
    if (lib.existsSync()) DynamicLibrary.open(lib.path);
  }
}
