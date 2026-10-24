/// The sync engine's persisted state: the merged copy of every synced node,
/// which nodes still need pushing, and the change-detection bookkeeping.
///
/// One KeyValueStore entry per node (`sync.node.<path>`) so a write-through
/// rewrites a few hundred bytes rather than the whole library.
library;

import 'dart:convert';

import 'package:kartka/platform/key_value_store.dart';
import 'package:kartka/sync/merge/merge_rules.dart';

const _nodePrefix = 'sync.node.';
const _dirtyKey = 'sync.dirty';
const _revKey = 'sync.rev';
const _peersKey = 'sync.peers';
const _lastSyncKey = 'sync.lastSync';
const _hlcKey = 'sync.hlc';

/// In-memory mirror of the persisted sync state, written through on change.
class SyncShadow {
  new _(this._store);

  /// Loads the state persisted in [store] (empty on first run).
  static Future<SyncShadow> load(KeyValueStore store) async {
    final shadow = SyncShadow._(store);
    final entries = await store.entries(prefix: _nodePrefix);
    for (final e in entries.entries) {
      final decoded = _decodeMap(e.value);
      if (decoded != null) {
        shadow._nodes[e.key.substring(_nodePrefix.length)] = decoded;
      }
    }
    final dirty = jsonDecode(await store.get(_dirtyKey) ?? '[]');
    if (dirty is List) shadow._dirty.addAll(dirty.whereType<String>());
    shadow
      .._rev = int.tryParse(await store.get(_revKey) ?? '') ?? 0
      ..peers = {
        for (final e in (_decodeMap(await store.get(_peersKey)) ?? {}).entries)
          e.key: '${e.value}',
      }
      ..lastSync = DateTime.tryParse(await store.get(_lastSyncKey) ?? '')
      ..lastHlc = await store.get(_hlcKey);
    return shadow;
  }

  final KeyValueStore _store;
  final Map<String, Node> _nodes = {};
  final Set<String> _dirty = {};
  int _rev = 0;

  /// Revisions last seen per peer device (own device excluded).
  Map<String, String> peers = {};

  /// When a full sync last completed.
  DateTime? lastSync;

  /// The last Hlc this device issued or observed, as its string form.
  String? lastHlc;

  /// Every node path held, e.g. `library/<h>`.
  Iterable<String> get paths => _nodes.keys;

  /// Paths changed locally (or found behind) and not yet pushed.
  Set<String> get dirty => Set.unmodifiable(_dirty);

  /// The merged node at [path], or null.
  Node? node(String path) => _nodes[path];

  /// Every node under namespace [ns] (`library`, `read`, ...), by path.
  Map<String, Node> namespace(String ns) => {
    for (final e in _nodes.entries)
      if (e.key.startsWith('$ns/')) e.key: e.value,
  };

  /// Stores [node] at [path], optionally marking it for push.
  Future<void> put(String path, Node node, {required bool dirty}) async {
    _nodes[path] = node;
    await _store.set('$_nodePrefix$path', canon(node));
    if (dirty && _dirty.add(path)) await _saveDirty();
  }

  /// Marks [path] for push without changing it.
  Future<void> markDirty(String path) async {
    if (_dirty.add(path)) await _saveDirty();
  }

  /// Forgets [pushed] from the dirty set after a successful push.
  Future<void> clearDirty(Iterable<String> pushed) async {
    _dirty.removeAll(pushed);
    await _saveDirty();
  }

  /// Returns the next own revision counter and persists it.
  Future<int> nextRev() async {
    _rev++;
    await _store.set(_revKey, '$_rev');
    return _rev;
  }

  /// Persists [peers], [lastSync] and [lastHlc].
  Future<void> saveMeta() async {
    await _store.set(_peersKey, jsonEncode(peers));
    final at = lastSync;
    if (at != null) await _store.set(_lastSyncKey, at.toIso8601String());
    final hlc = lastHlc;
    if (hlc != null) await _store.set(_hlcKey, hlc);
  }

  Future<void> _saveDirty() => _store.set(_dirtyKey, jsonEncode([..._dirty]));

  static Map<String, Object?>? _decodeMap(String? text) {
    if (text == null) return null;
    try {
      final decoded = jsonDecode(text);
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      return null;
    }
  }
}
