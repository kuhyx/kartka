import 'dart:convert';

import 'package:kartka/platform/key_value_store.dart';

/// Extension packages the user uninstalled, stored per device (installs are
/// per device, like `AutoInstallState`). The Keep auto-install skips them,
/// even when the library still uses one; installing one by hand clears its
/// mark. Auto-update never sees them: it only updates installed packages.
class UninstallMarks {
  /// Marks kept in [kv].
  const new(this.kv);

  /// Device-local storage.
  final KeyValueStore kv;

  /// Key in [kv]: a JSON list of package names.
  static const String kvKey = 'sourceHealth.userUninstalled';

  /// The marked packages; empty when absent or unreadable.
  Future<Set<String>> load() async {
    final raw = await kv.get(kvKey);
    if (raw == null) return {};
    try {
      final list = jsonDecode(raw);
      return list is List ? {...list.whereType<String>()} : {};
    } on FormatException {
      return {};
    }
  }

  /// Marks [pkg] as uninstalled by the user.
  Future<void> mark(String pkg) async => await _save({...await load(), pkg});

  /// Clears [pkg]'s mark (an install by hand).
  Future<void> clear(String pkg) async {
    final marks = await load();
    if (marks.remove(pkg)) await _save(marks);
  }

  Future<void> _save(Set<String> marks) =>
      kv.set(kvKey, jsonEncode(marks.toList()..sort()));
}
