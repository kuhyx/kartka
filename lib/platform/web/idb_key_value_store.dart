import 'package:idb_shim/idb.dart';
import 'package:kartka/platform/key_value_store.dart';

/// [KeyValueStore] in IndexedDB (web build).
///
/// IndexedDB rather than localStorage: localStorage caps at ~5-10 MB per
/// origin and is evicted more eagerly. Pure `idb_shim`, so tests run it on
/// the in-memory factory.
class IdbKeyValueStore implements KeyValueStore {
  new _(this._db);

  /// Opens (creating if needed) the store in [factory].
  static Future<IdbKeyValueStore> open(IdbFactory factory) async {
    final db = await factory.open(
      databaseName,
      version: 1,
      onUpgradeNeeded: (event) {
        if (!event.database.objectStoreNames.contains(storeName)) {
          event.database.createObjectStore(storeName);
        }
      },
    );
    return IdbKeyValueStore._(db);
  }

  /// IndexedDB database name.
  static const databaseName = 'kartka';

  /// Object store name.
  static const storeName = 'kv';

  final Database _db;

  Future<T> _run<T>(String mode, Future<T> Function(ObjectStore s) body) async {
    final txn = _db.transaction(storeName, mode);
    final result = await body(txn.objectStore(storeName));
    await txn.completed;
    return result;
  }

  @override
  Future<String?> get(String key) =>
      _run(idbModeReadOnly, (s) async => await s.getObject(key) as String?);

  @override
  Future<void> set(String key, String value) =>
      _run(idbModeReadWrite, (s) => s.put(value, key));

  @override
  Future<void> remove(String key) =>
      _run(idbModeReadWrite, (s) => s.delete(key));

  /// Visits only keys in `[prefix, prefix + U+FFFF]` (IndexedDB orders
  /// strings by UTF-16 code unit, so that is every key starting with
  /// [prefix]), not the whole store: the startup reads of each table no
  /// longer scan every other table's rows too.
  @override
  Future<Map<String, String>> entries({String prefix = ''}) =>
      _run(idbModeReadOnly, (s) async {
        final result = <String, String>{};
        final range = prefix.isEmpty
            ? null
            : KeyRange.bound(prefix, '$prefix\uffff');
        await s.openCursor(range: range, autoAdvance: true).forEach((c) {
          final key = c.key as String;
          if (key.startsWith(prefix)) result[key] = c.value as String;
        });
        return result;
      });
}
