import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

/// Loads flutter_js's bundled Linux QuickJS library into the process.
void preloadQuickJs() {
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
