/// Write-through + pull-merge sync of the §4 nodes (DOCS-contracts §4, §12).
///
/// Local writes merge into the `SyncShadow` and are pushed at once (or, for
/// [SyncEngine.writeDeferred], within a few seconds), publishing a revision
/// and change-feed entry in the same atomic update (`sync_feed.dart`).
/// [SyncEngine.poll] reads only `revs/`, then the feed, then just the changed
/// nodes. Every pulled node is merged with the shadow, changes are emitted on
/// [SyncEngine.remoteChanges], and anything the remote is behind on is pushed
/// back, which also heals a write lost to a concurrent PATCH of one node.
library;

import 'dart:async';

import 'package:crdt_sync/crdt_sync.dart' show Hlc, RemoteSyncError;
import 'package:kartka/core/redact.dart';
import 'package:kartka/sync/merge/merge_rules.dart';
import 'package:kartka/sync/rtdb_transport.dart';
import 'package:kartka/sync/sync_feed.dart';
import 'package:kartka/sync/sync_namespaces.dart';
import 'package:kartka/sync/sync_shadow.dart';
import 'package:kartka/sync/sync_status.dart';

export 'package:kartka/sync/sync_namespaces.dart';

/// The sync engine; one per app.
class SyncEngine {
  /// Creates an engine for [deviceId] over [shadow].
  new({
    required this.shadow,
    required this.deviceId,
    required this.open,
    DateTime Function()? now,
    this.deferFor = const Duration(seconds: 3),
  }) : _now = now ?? DateTime.now;

  /// Persisted state.
  final SyncShadow shadow;

  /// This install's id (never a constant): the Hlc node id and revs key.
  final String deviceId;

  /// Transport factory; called again after a failure or a sign-out.
  final TransportOpener open;

  /// How long [writeDeferred] may hold a push back.
  final Duration deferFor;

  final DateTime Function() _now;
  final _changes = StreamController<RemoteChange>.broadcast();
  final _status = StreamController<SyncStatus>.broadcast();
  // "Checking" until the first poll learns whether this device is signed in.
  late SyncStatus _current = SyncStatus(
    phase: SyncPhase.syncing,
    lastSync: shadow.lastSync,
  );
  RtdbTransport? _transport;
  Timer? _deferred;
  Future<void> _queue = Future.value();

  /// Nodes changed by merging in a peer's writes.
  Stream<RemoteChange> get remoteChanges => _changes.stream;

  /// The latest status.
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

  /// Merges [node] into the shadow at [path] and pushes it now.
  Future<void> write(String path, Node node) => writeAll({path: node});

  /// Merges every node in [nodes] and pushes them in one atomic update.
  Future<void> writeAll(Map<String, Node> nodes) => _serial(() async {
    if (await _mergeLocal(nodes)) await _push(await _connect());
  });

  /// Like [write], but the push waits up to [deferFor], so a burst (page
  /// turns) costs one push. [flush] sends it early (chapter change, pause).
  Future<void> writeDeferred(String path, Node node) => _serial(() async {
    if (!await _mergeLocal({path: node})) return;
    _deferred ??= Timer(deferFor, () => unawaited(flush()));
  });

  /// Pushes anything [writeDeferred] is holding back.
  Future<void> flush() => _serial(() async {
    _deferred?.cancel();
    _deferred = null;
    await _push(await _connect());
  });

  /// Cheap change check: revs, then the feed, then only changed nodes.
  Future<void> poll() => _serial(() => _sync(force: false));

  /// Full pull + push regardless of revisions (the "Sync now" button).
  Future<void> syncNow() => _serial(() => _sync(force: true));

  /// Records that a decorator replayed [path] into its local repository.
  void ack(String path) => shadow.ack(path);

  /// Drops the cached transport, e.g. after signing in or out.
  void reset() => _transport = null;

  Future<bool> _mergeLocal(Map<String, Node> nodes) async {
    var changed = false;
    // Memory only per node; one save for the whole batch.
    for (final MapEntry(key: path, value: node) in nodes.entries) {
      final merge = kSyncNamespaces[path.split('/').first]!.$2;
      final old = shadow.node(path);
      final merged = old == null ? node : merge(old, node);
      if (old != null && canon(merged) == canon(old)) continue;
      shadow.put(path, merged, dirty: true);
      changed = true;
    }
    await shadow.save();
    return changed;
  }

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
      final plan = force
          ? (full: true, paths: <String>{})
          : await planPull(transport, peers, shadow.peers);
      if (plan.full) {
        for (final ns in kSyncNamespaces.keys) {
          await _pullNamespace(transport, ns);
        }
      } else {
        for (final path in plan.paths) {
          final node = fromRtdb(await transport.get(path));
          if (node is Map<String, Object?>) _mergeRemote(path, node);
        }
      }
      shadow.peers = peers;
      await shadow.save();
      await _push(transport);
      shadow.lastSync = _now();
      await shadow.save();
      _emit(SyncStatus(phase: SyncPhase.idle, lastSync: shadow.lastSync));
    } on RemoteSyncError catch (e) {
      _fail(e);
    }
  }

  Future<void> _pullNamespace(RtdbTransport transport, String ns) async {
    final remote = flattenNodes(
      ns,
      await transport.get(ns),
      kSyncNamespaces[ns]!.$1,
    );
    for (final MapEntry(key: path, value: theirs) in remote.entries) {
      _mergeRemote(path, theirs);
    }
    for (final path in shadow.namespace(ns).keys) {
      if (!remote.containsKey(path)) shadow.markDirty(path);
    }
  }

  void _mergeRemote(String path, Node theirs) {
    final rule = kSyncNamespaces[path.split('/').first];
    if (rule == null) return;
    shadow.lastHlc = newestClock(theirs, shadow.lastHlc);
    final mine = shadow.node(path);
    final merged = mine == null ? theirs : rule.$2(mine, theirs);
    final behind = canon(merged) != canon(theirs);
    if (mine == null || canon(merged) != canon(mine)) {
      shadow
        ..put(path, merged, dirty: behind)
        // Persisted with the node, so a change no decorator was listening
        // for yet (or a crash before replay) is replayed, never lost.
        ..markUnapplied(path);
      _changes.add((path: path, node: merged));
    } else if (behind) {
      shadow.markDirty(path);
    }
  }

  Future<void> _push(RtdbTransport? transport) async {
    if (transport == null) return;
    try {
      if (!await pushDirty(transport, shadow, deviceId)) return;
      await shadow.save();
      if (_current.phase == SyncPhase.error) {
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

  void _fail(RemoteSyncError e) {
    // The transport may hold an expired session; reopen on the next call.
    _transport = null;
    _emit(
      SyncStatus(
        phase: SyncPhase.error,
        lastSync: shadow.lastSync,
        message: redactUrlQueries(e.message),
      ),
    );
  }

  void _emit(SyncStatus s) {
    _current = s;
    _status.add(s);
  }

  Future<void> _serial(Future<void> Function() job) =>
      _queue = _queue.then((_) => job());

  /// Cancels the deferred push timer and closes the streams.
  Future<void> dispose() async {
    _deferred?.cancel();
    await _changes.close();
    await _status.close();
  }
}
