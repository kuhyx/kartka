/// The sync engine's persisted state: the merged copy of every synced node,
/// which nodes still need pushing or replaying, and change-detection
/// bookkeeping.
///
/// Write-behind and bucketed, because Android's KeyValueStore rewrites its
/// whole file on every `set`: nodes live in one entry per `<ns>/<k1>`
/// bucket (all read marks of a manga together), mutations only touch memory,
/// and [SyncShadow.save] writes each changed bucket once per engine
/// operation. A 25k-mark import is then ~800 bucket writes, not 25k.
library;

import 'dart:async';
import 'dart:convert';

import 'package:kartka/platform/key_value_store.dart';
import 'package:kartka/sync/merge/merge_rules.dart';

const _bucketPrefix = 'sync.b.';
const _dirtyKey = 'sync.dirty';
const _unappliedKey = 'sync.unapplied';
const _revKey = 'sync.rev';
const _peersKey = 'sync.peers';
const _lastSyncKey = 'sync.lastSync';
const _hlcKey = 'sync.hlc';

/// In-memory mirror of the persisted sync state.
class SyncShadow {
  new _(this._store);

  /// Loads the state persisted in [store] (empty on first run).
  static Future<SyncShadow> load(KeyValueStore store) async {
    final s = SyncShadow._(store);
    for (final raw in (await store.entries(prefix: _bucketPrefix)).values) {
      for (final e in (_decodeMap(raw) ?? const {}).entries) {
        if (e.value case final Map<String, Object?> node) s._set(e.key, node);
      }
    }
    s._dirty.addAll(_decodeList(await store.get(_dirtyKey)));
    s._unapplied.addAll(_decodeList(await store.get(_unappliedKey)));
    s
      .._rev = int.tryParse(await store.get(_revKey) ?? '') ?? 0
      ..peers = {
        for (final e in (_decodeMap(await store.get(_peersKey)) ?? {}).entries)
          e.key: '${e.value}',
      }
      ..lastSync = DateTime.tryParse(await store.get(_lastSyncKey) ?? '')
      ..lastHlc = await store.get(_hlcKey);
    return s;
  }

  final KeyValueStore _store;
  final Map<String, Map<String, Node>> _buckets = {};
  final Set<String> _dirty = {};
  final Set<String> _unapplied = {};
  final Set<String> _changedBuckets = {};
  bool _dirtyChanged = false;
  bool _unappliedChanged = false;
  int _rev = 0;
  Timer? _soon;

  /// Revisions last seen per peer device (own device excluded).
  Map<String, String> peers = {};

  /// When a full sync last completed.
  DateTime? lastSync;

  /// The last Hlc this device issued or observed, as its string form.
  String? lastHlc;

  /// Every node path held, e.g. `library/<h>`.
  Iterable<String> get paths => _buckets.values.expand((b) => b.keys);

  /// Paths changed locally (or found behind) and not yet pushed.
  Set<String> get dirty => Set.unmodifiable(_dirty);

  /// Paths merged from a peer but not yet replayed into a local repo.
  Set<String> get unapplied => Set.unmodifiable(_unapplied);

  /// The merged node at [path], or null.
  Node? node(String path) => _buckets[_bucket(path)]?[path];

  /// Every node under namespace [ns] (`library`, `read`, ...), by path.
  Map<String, Node> namespace(String ns) => {
    for (final b in _buckets.entries)
      if (b.key.startsWith('$ns/')) ...b.value,
  };

  /// Stores [node] at [path] in memory; persisted by the next [save].
  void put(String path, Node node, {required bool dirty}) {
    _changedBuckets.add(_set(path, node));
    if (dirty) markDirty(path);
  }

  /// Marks [path] for push.
  void markDirty(String path) => _dirtyChanged |= _dirty.add(path);

  /// Forgets [pushed] from the dirty set after a successful push.
  void clearDirty(Iterable<String> pushed) {
    _dirty.removeAll(pushed);
    _dirtyChanged = true;
  }

  /// Marks [path] as merged from a peer but not yet replayed locally.
  void markUnapplied(String path) => _unappliedChanged |= _unapplied.add(path);

  /// Records that [path] was replayed; persisted shortly after, coalesced.
  void ack(String path) {
    if (!_unapplied.remove(path)) return;
    _unappliedChanged = true;
    _soon ??= Timer(const Duration(milliseconds: 200), () => unawaited(save()));
  }

  /// Returns the next own revision counter, persisted before it is used:
  /// reusing a published revision would make peers skip a push.
  Future<int> nextRev() async {
    _rev++;
    await _store.set(_revKey, '$_rev');
    return _rev;
  }

  /// Writes every changed bucket and set once, plus the metadata.
  Future<void> save() async {
    _soon?.cancel();
    _soon = null;
    final buckets = [..._changedBuckets];
    _changedBuckets.clear();
    for (final b in buckets) {
      await _store.set('$_bucketPrefix$b', canon(_buckets[b]));
    }
    if (_dirtyChanged) {
      _dirtyChanged = false;
      await _store.set(_dirtyKey, jsonEncode([..._dirty]));
    }
    if (_unappliedChanged) {
      _unappliedChanged = false;
      await _store.set(_unappliedKey, jsonEncode([..._unapplied]));
    }
    await _store.set(_peersKey, jsonEncode(peers));
    final at = lastSync;
    if (at != null) await _store.set(_lastSyncKey, at.toIso8601String());
    final hlc = lastHlc;
    if (hlc != null) await _store.set(_hlcKey, hlc);
  }

  String _set(String path, Node node) {
    final bucket = _bucket(path);
    (_buckets[bucket] ??= {})[path] = node;
    return bucket;
  }

  static String _bucket(String path) => path.split('/').take(2).join('/');

  static List<String> _decodeList(String? text) {
    try {
      final decoded = jsonDecode(text ?? '[]');
      return decoded is List ? decoded.whereType<String>().toList() : [];
    } on FormatException {
      return [];
    }
  }

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
