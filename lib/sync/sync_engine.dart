/// Write-through + pull-merge sync of the §4 nodes (DOCS-contracts §4, §12).
///
/// Local writes merge into the `SyncShadow` and are pushed at once, with a
/// bump of `revs/<deviceId>` in the same atomic update. `SyncEngine.poll`
/// reads only the tiny `revs/` node and pulls the subtrees when a peer's
/// revision moved; every pulled node is merged with the shadow, changes are
/// emitted on `SyncEngine.remoteChanges`, and anything the remote is behind
/// on is pushed back, which also heals a write lost to a concurrent PATCH of
/// the same node.
library;

import 'dart:async';

import 'package:crdt_sync/crdt_sync.dart' show Hlc, RemoteSyncError;
import 'package:kartka/sync/merge/merge_rules.dart';
import 'package:kartka/sync/rtdb_transport.dart';
import 'package:kartka/sync/sync_shadow.dart';
import 'package:kartka/sync/sync_status.dart';

/// Merge rule and key depth of each synced namespace.
const Map<String, (int, Merge)> kSyncNamespaces = {
  'library': (1, mergeLwwNode),
  'categories': (1, mergeLwwNode),
  'membership': (2, mergeRegister),
  'progress': (1, mergeProgress),
  'read': (2, mergeRegister),
};

/// One node that changed because of a remote merge.
typedef RemoteChange = ({String path, Node node});

/// Opens a transport, or returns null while this device is signed out.
typedef TransportOpener = Future<RtdbTransport?> Function();

/// The sync engine; one per app.
class SyncEngine {
  /// Creates an engine for [deviceId] over [shadow].
  new({
    required this.shadow,
    required this.deviceId,
    required this.open,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// Persisted state.
  final SyncShadow shadow;

  /// This install's id (never a constant): the Hlc node id and revs key.
  final String deviceId;

  /// Transport factory; called again after a failure or a sign-out.
  final TransportOpener open;

  final DateTime Function() _now;
  final _changes = StreamController<RemoteChange>.broadcast();
  final _status = StreamController<SyncStatus>.broadcast();
  late SyncStatus _current = SyncStatus(
    phase: SyncPhase.idle,
    lastSync: shadow.lastSync,
  );
  RtdbTransport? _transport;
  Future<void> _queue = Future.value();

  /// Nodes changed by merging in a peer's writes.
  Stream<RemoteChange> get remoteChanges => _changes.stream;

  /// The latest status, then every change.
  SyncStatus get status => _current;

  /// Status changes.
  Stream<SyncStatus> get statusChanges => _status.stream;

  /// The next local Hlc: strictly after everything issued or observed.
  Hlc tick() {
    final last = shadow.lastHlc;
    final next = Hlc.newTick(
      deviceId,
      previous: last == null ? null : Hlc.fromStr(last),
      wallTimeMsOverride: _now().toUtc().millisecondsSinceEpoch,
    );
    shadow.lastHlc = next.toStr();
    return next;
  }

  /// Merges [node] into the shadow at [path] and pushes it (write-through).
  Future<void> write(String path, Node node) => _serial(() async {
    final merge = kSyncNamespaces[path.split('/').first]!.$2;
    final old = shadow.node(path);
    await shadow.put(path, old == null ? node : merge(old, node), dirty: true);
    await shadow.saveMeta();
    await _push(await _connect());
  });

  /// Cheap change check: pulls only when a peer's revision moved.
  Future<void> poll() => _serial(() => _sync(force: false));

  /// Full pull + push regardless of revisions (the "Sync now" button).
  Future<void> syncNow() => _serial(() => _sync(force: true));

  /// Drops the cached transport, e.g. after signing out.
  void reset() => _transport = null;

  Future<void> _sync({required bool force}) async {
    final transport = await _connect();
    if (transport == null) return;
    _emit(_current.copyWith(phase: SyncPhase.syncing));
    try {
      final revs = await transport.get('revs');
      final peers = <String, String>{
        if (revs is Map)
          for (final e in revs.entries)
            if (e.key != deviceId) '${e.key}': '${e.value}',
      };
      if (force || !_sameMap(peers, shadow.peers)) {
        for (final ns in kSyncNamespaces.keys) {
          await _pullNamespace(transport, ns);
        }
        shadow.peers = peers;
      }
      await _push(transport);
      shadow.lastSync = _now();
      await shadow.saveMeta();
      _emit(SyncStatus(phase: SyncPhase.idle, lastSync: shadow.lastSync));
    } on RemoteSyncError catch (e) {
      _fail(e);
    }
  }

  Future<void> _pullNamespace(RtdbTransport transport, String ns) async {
    final (depth, merge) = kSyncNamespaces[ns]!;
    final remote = flattenNodes(ns, await transport.get(ns), depth);
    for (final MapEntry(key: path, value: theirs) in remote.entries) {
      _observeClocks(theirs);
      final mine = shadow.node(path);
      final merged = mine == null ? theirs : merge(mine, theirs);
      final behind = canon(merged) != canon(theirs);
      if (mine == null || canon(merged) != canon(mine)) {
        await shadow.put(path, merged, dirty: behind);
        _changes.add((path: path, node: merged));
      } else if (behind) {
        await shadow.markDirty(path);
      }
    }
    for (final path in shadow.namespace(ns).keys) {
      if (!remote.containsKey(path)) await shadow.markDirty(path);
    }
  }

  Future<void> _push(RtdbTransport? transport) async {
    if (transport == null) return;
    final pending = shadow.dirty;
    if (pending.isEmpty) return;
    try {
      await transport.patch({
        for (final path in pending) path: shadow.node(path),
        'revs/$deviceId': '${await shadow.nextRev()}',
      });
      await shadow.clearDirty(pending);
      if (_current.phase != SyncPhase.idle) {
        _emit(SyncStatus(phase: SyncPhase.idle, lastSync: shadow.lastSync));
      }
    } on RemoteSyncError catch (e) {
      _fail(e);
    }
  }

  Future<RtdbTransport?> _connect() async {
    try {
      _transport ??= await open();
    } on RemoteSyncError catch (e) {
      _fail(e);
      return null;
    }
    if (_transport == null) {
      _emit(SyncStatus(phase: SyncPhase.signedOut, lastSync: shadow.lastSync));
    }
    return _transport;
  }

  void _observeClocks(Node node) {
    final clocks = [
      if (node[kHlcField] case final String c) c,
      if (node[kHlcField] case final Map<Object?, Object?> m)
        ...m.values.whereType<String>(),
    ];
    for (final c in clocks) {
      if (compareHlc(c, shadow.lastHlc) > 0) shadow.lastHlc = c;
    }
  }

  void _fail(RemoteSyncError e) {
    // The transport may hold an expired session; reopen on the next call.
    _transport = null;
    _emit(
      SyncStatus(
        phase: SyncPhase.error,
        lastSync: shadow.lastSync,
        message: e.message,
      ),
    );
  }

  void _emit(SyncStatus s) {
    _current = s;
    _status.add(s);
  }

  Future<void> _serial(Future<void> Function() job) =>
      _queue = _queue.then((_) => job());

  /// Closes the streams.
  Future<void> dispose() async {
    await _changes.close();
    await _status.close();
  }
}

/// Flattens a namespace subtree into `{<ns>/<k1>[/<k2>]: node}`.
Map<String, Node> flattenNodes(String ns, Object? tree, int depth) {
  final out = <String, Node>{};
  void walk(String prefix, Object? node, int level) {
    if (node is! Map<String, Object?>) return;
    if (level == depth) {
      out[prefix] = node;
      return;
    }
    for (final e in node.entries) {
      walk('$prefix/${e.key}', e.value, level + 1);
    }
  }

  walk(ns, tree, 0);
  return out;
}

bool _sameMap(Map<String, String> a, Map<String, String> b) =>
    a.length == b.length && a.entries.every((e) => b[e.key] == e.value);
