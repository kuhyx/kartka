import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:kartka/platform/key_value_store.dart';

/// [KeyValueStore] in the Android Keystore (`KartkaPlatform.secrets`).
///
/// Keys are namespaced `kartka.` so other entries in the same storage are
/// never listed or touched.
class SecureKeyValueStore implements KeyValueStore {
  /// Stores through [storage].
  new(this.storage);

  /// The plugin.
  final FlutterSecureStorage storage;

  static const _ns = 'kartka.';

  @override
  Future<String?> get(String key) => storage.read(key: '$_ns$key');

  @override
  Future<void> set(String key, String value) =>
      storage.write(key: '$_ns$key', value: value);

  @override
  Future<void> remove(String key) => storage.delete(key: '$_ns$key');

  @override
  Future<Map<String, String>> entries({String prefix = ''}) async => {
    for (final e in (await storage.readAll()).entries)
      if (e.key.startsWith('$_ns$prefix')) e.key.substring(_ns.length): e.value,
  };
}
