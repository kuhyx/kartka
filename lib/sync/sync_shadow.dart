/// The sync engine's persisted state: the merged copy of every synced node,
/// which nodes still need pushing or replaying, and change-detection
/// bookkeeping.
///
/// Write-behind and bucketed, because every Android KeyValueStore `set`
/// rewrites a whole shard file: nodes live in one entry per `<ns>/<k1>`
/// bucket (all read marks of a manga together), mutations only touch memory,
/// and [SyncShadow.save] writes each changed bucket once per engine
/// operation. A 25k-mark import is then ~800 bucket writes, not 25k.
library;

import 'dart:async';
import 'dart:convert';

import 'package:kartka/platform/key_value_store.dart';
import 'package:kartka/sync/merge/merge_rules.dart';
import 'package:kartka/sync/off_ui_json.dart';

const _bucketPrefix = 'sync.b.';
const _dirtyKey = 'sync.dirty';
const _unappliedKey = 'sync.unapplied';
const _revKey = 'sync.rev';
const _peersKey = 'sync.peers';
const _lastSyncKey = 'sync.lastSync';
const _hlcKey = 'sync.hlc';
const _legacyKey = 'sync.legacyRevs';

/// In-memory mirror of the persisted sync state.
class SyncShadow {
  new _(this._store);

  /// Loads the state persisted in [store] (empty on first run).
  static Future<SyncShadow> load(KeyValueStore store) async {
    final s = SyncShadow._(store);
    // Every bucket and both lists at once: a mirror of the whole library
    // (unapplied can be every path after a first pull), so big ones are
    // decoded off the UI isolate in one run.
    final raw = (await store.entries(prefix: _bucketPrefix)).values.toList();
    final decoded = await decodeEachOffUi([
      ...raw,
      await store.get(_dirtyKey) ?? '[]',
      await store.get(_unappliedKey) ?? '[]',
    ]);
    for (final bucket in decoded.take(raw.length)) {
      if (bucket is! Map<String, Object?>) continue;
      for (final e in bucket.entries) {
        if (e.value case final Map<String, Object?> node) s._set(e.key, node);
      }
    }
    s._dirty.addAll(_strings(decoded[raw.length]));
    s._unapplied.addAll(_strings(decoded[raw.length + 1]));
    for (final key in [_peersKey, _lastSyncKey, _hlcKey, _legacyKey]) {
      if (await store.get(key) case final value?) s._persisted[key] = value;
    }
    s
      .._rev = int.tryParse(await store.get(_revKey) ?? '') ?? 0
      ..peers = {
        for (final e in (_decodeMap(s._persisted[_peersKey]) ?? {}).entries)
          e.key: '${e.value}',
      }
      ..lastSync = DateTime.tryParse(s._persisted[_lastSyncKey] ?? '')
      ..lastHlc = s._persisted[_hlcKey]
      ..legacyRevs = s._persisted[_legacyKey];
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
  // The metadata strings as last read or written, so unchanged ones skip.
  final Map<String, String> _persisted = {};
  bool _clockDue = false;

  /// Revisions last seen per peer device (own device excluded).
  Map<String, String> peers = {};

  /// When a full sync last completed.
  DateTime? lastSync;

  /// The last Hlc this device issued or observed, as its string form.
  String? lastHlc;

  /// The old `/kartka` revisions last copied into the e2e root.
  String? legacyRevs;

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

  /// Writes every changed bucket, set and metadata value once; an
  /// unchanged one is not rewritten, so a no-op poll writes nothing.
  ///
  /// [lastSync] changes on every poll, so it is only written alongside
  /// another change or when [withClock] (the pause flush) asks for it.
  Future<void> save({bool withClock = false}) async {
    _soon?.cancel();
    _soon = null;
    final buckets = [..._changedBuckets];
    _changedBuckets.clear();
    var wrote = buckets.isNotEmpty;
    for (final b in buckets) {
      await _store.set('$_bucketPrefix$b', canon(_buckets[b]));
    }
    if (_dirtyChanged) {
      _dirtyChanged = false;
      wrote = true;
      await _store.set(_dirtyKey, jsonEncode([..._dirty]));
    }
    if (_unappliedChanged) {
      _unappliedChanged = false;
      wrote = true;
      await _store.set(_unappliedKey, jsonEncode([..._unapplied]));
    }
    wrote |= await _put(_peersKey, jsonEncode(peers));
    wrote |= await _put(_hlcKey, lastHlc);
    wrote |= await _put(_legacyKey, legacyRevs);
    // Due from a save that changed something until a lastSync is written
    // (the engine sets it only after that save, at the end of a sync).
    _clockDue |= wrote;
    final at = lastSync;
    if ((_clockDue || withClock) && at != null) {
      await _put(_lastSyncKey, at.toIso8601String());
      _clockDue = false;
    }
  }

  /// Writes [value] under [key] unless it is null or what was last
  /// persisted there; true when it wrote.
  Future<bool> _put(String key, String? value) async {
    if (value == null || _persisted[key] == value) return false;
    await _store.set(key, value);
    _persisted[key] = value;
    return true;
  }

  String _set(String path, Node node) {
    final bucket = _bucket(path);
    (_buckets[bucket] ??= {})[path] = node;
    return bucket;
  }

  static String _bucket(String path) => path.split('/').take(2).join('/');

  static List<String> _strings(Object? decoded) =>
      decoded is List ? decoded.whereType<String>().toList() : [];

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
