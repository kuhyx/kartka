/// The [SettingsSync] sync supplies (DOCS-contracts-runtime §16).
///
/// A local write becomes `settings/<key>` = `{key, value, hlc}` (plain) or
/// `{key, enc, hlc}` (secret, sealed by [SettingsCipher]); a removal keeps
/// only `{key, hlc}`. Nodes merge whole-node LWW on the Hlc, like `read/`,
/// and ride the engine's normal push, change feed and pull. A peer's node is
/// written straight into the platform store (never back through a
/// `SyncedKeyValueStore`, so nothing echoes) and announced on
/// `remoteChanges`.
library;

import 'dart:async';
import 'dart:developer';

import 'package:crdt_sync_flutter/crdt_sync_flutter.dart' show storedAccount;
import 'package:kartka/core/settings/settings_sync.dart';
import 'package:kartka/platform/key_value_store.dart';
import 'package:kartka/sync/merge/merge_rules.dart';
import 'package:kartka/sync/settings/settings_catalog.dart';
import 'package:kartka/sync/settings/settings_cipher.dart';
import 'package:kartka/sync/sync_engine.dart';

/// The sync account password crdt_sync_flutter keeps in the keystore, or
/// null when this device has none (a Google or seeded-session sign-in).
Future<String?> storedSyncPassword() async {
  final password = (await storedAccount())?.password;
  return password == null || password.isEmpty ? null : password;
}

const _noPassword = 'sign in to sync with a password';

/// Syncs the catalogued settings through one [SyncEngine].
class SyncedSettings implements SettingsSync {
  /// Attaches once [started] completes; [start] starts the engine for a
  /// local write. Neither runs while the registry is built.
  new({
    required Future<SyncEngine> started,
    required this.start,
    required this.kv,
    required this.secrets,
    required this.syncPassword,
    SettingsCipher? cipher,
  }) : cipher = cipher ?? SettingsCipher() {
    unawaited(started.then(_attach, onError: (Object _) {}));
  }

  /// Starts (or returns) the engine.
  final Future<SyncEngine> Function() start;

  /// The platform's plain store.
  final KeyValueStore kv;

  /// The platform's secret store.
  final KeyValueStore secrets;

  /// The sync account password; null when this device has none.
  final Future<String?> Function() syncPassword;

  /// Seals and opens secret values.
  final SettingsCipher cipher;

  final _remote = StreamController<String>.broadcast();
  final _problemChanges = StreamController<Map<String, String>>.broadcast();
  final Map<String, String> _problems = {};
  Future<void> _queue = Future.value();

  @override
  Stream<String> get remoteChanges => _remote.stream;

  @override
  Stream<Map<String, String>> watchProblems() async* {
    yield Map.unmodifiable(_problems);
    yield* _problemChanges.stream;
  }

  /// Completes once every change queued so far is published or replayed.
  Future<void> get settled => _queue;

  @override
  Future<void> changed(String key, String? value, SettingsVault vault) async {
    final setting = kSyncedSettings[key];
    if (setting == null || setting.vault != vault) return;
    _serial(() async {
      final engine = await start().then<SyncEngine?>(
        (e) => e,
        onError: (Object _) => null,
      );
      if (engine == null) return;
      final node = await _encode(engine, key, setting, value);
      if (node != null) await engine.write(settingPath(key), node);
    });
  }

  Future<Node?> _encode(
    SyncEngine engine,
    String key,
    SyncedSetting setting,
    String? value,
  ) async {
    final old = engine.shadow.node(settingPath(key));
    if (setting.vault == SettingsVault.plain) {
      // Unchanged: re-stamping could beat a newer value still in flight.
      if (old?['value'] == value) return null;
      return {'key': key, 'value': ?value, kHlcField: engine.tick().toStr()};
    }
    final password = await syncPassword();
    if (password == null) {
      _problem(key, '${setting.label} not synced: $_noPassword');
      return null;
    }
    _problem(key, null);
    final enc = old?['enc'];
    if (enc == null
        ? value == null
        : value != null && await _open(enc, key, password) == value) {
      return null;
    }
    final sealed = value == null
        ? null
        : await cipher.seal(value, password: password, context: key);
    return {'key': key, 'enc': ?sealed, kHlcField: engine.tick().toStr()};
  }

  Future<String?> _open(Object? enc, String key, String password) =>
      cipher.open(enc, password: password, context: key);

  void _attach(SyncEngine engine) {
    bool mine(String path) => path.startsWith('settings/');
    engine.remoteChanges
        .where((c) => mine(c.path))
        .listen((c) => _serial(() => _apply(engine, c)));
    for (final path in engine.shadow.unapplied.where(mine)) {
      final node = engine.shadow.node(path)!;
      _serial(() => _apply(engine, (path: path, node: node)));
    }
  }

  Future<void> _apply(SyncEngine engine, RemoteChange change) async {
    final (key, raw) = (change.node['key'], change.node['value']);
    final setting = key is String ? kSyncedSettings[key] : null;
    if (key is! String ||
        setting == null ||
        settingPath(key) != change.path ||
        (raw != null && raw is! String)) {
      // Hand-edited or foreign: never lets a peer write unlisted keys.
      engine.ack(change.path);
      return;
    }
    var value = raw as String?;
    final enc = change.node['enc'];
    if (setting.vault == SettingsVault.secret && enc != null) {
      final password = await syncPassword();
      value = password == null ? null : await _open(enc, key, password);
      if (value == null) {
        // Keep the local value; left unapplied, so the next start retries.
        final why = password == null ? ': no sync password here' : '';
        _problem(key, "Couldn't decrypt synced ${setting.label}$why");
        return;
      }
    }
    final store = setting.vault == SettingsVault.plain ? kv : secrets;
    if (await store.get(key) != value) {
      await (value == null ? store.remove(key) : store.set(key, value));
      _remote.add(key);
    }
    _problem(key, null);
    engine.ack(change.path);
  }

  void _problem(String key, String? message) {
    final old = _problems[key];
    if (old == message) return;
    if (message == null) {
      _problems.remove(key);
    } else {
      _problems[key] = message;
    }
    _problemChanges.add(Map.unmodifiable(_problems));
  }

  void _serial(Future<void> Function() job) => _queue = _queue.then((_) async {
    try {
      await job();
    } on Exception catch (e, st) {
      // A keystore or transport failure must not wedge later changes.
      log('settings sync step failed', error: e, stackTrace: st, level: 900);
    }
  });
}
