/// Shared plumbing of the sync decorators: wait for the engine, subscribe to
/// its remote changes for some namespaces, replay them in order.
library;

import 'dart:async';

import 'package:kartka/sync/sync_engine.dart';

/// Mixed into each decorator; call [listen] from the constructor.
mixin RemoteListener {
  /// The engine, which starts asynchronously after the repos are built;
  /// null when it failed to start, so local writes still work unsynced.
  late final Future<SyncEngine?> engine;

  StreamSubscription<RemoteChange>? _sub;
  Future<void> _applying = Future.value();
  final _buffer = <RemoteChange>[];
  bool _drainScheduled = false;

  /// Subscribes to [engine]'s changes under [namespaces] once it is ready.
  void listen(Future<SyncEngine> engine, Set<String> namespaces) {
    this.engine = engine.then<SyncEngine?>(
      (e) => e,
      onError: (Object _) => null,
    );
    unawaited(
      this.engine.then((e) {
        if (e == null) return;
        bool mine(String path) => namespaces.contains(path.split('/').first);
        _sub = e.remoteChanges
            .where((c) => mine(c.path))
            .listen((c) => _enqueue(e, c));
        // Changes merged before this repo existed (or before a crash) are
        // still marked unapplied: replay them. Re-applying is harmless,
        // the local repos are LWW / max.
        for (final path in e.shadow.unapplied.where(mine)) {
          _enqueue(e, (path: path, node: e.shadow.node(path)!));
        }
      }),
    );
  }

  // Changes arriving in one event-loop turn (a pull replaying N nodes, or
  // the startup replay) are replayed as one batch: every apply is started
  // before any is awaited, so the local repository sees a burst and its
  // watchers hear it once, not N times. Batches run one after another.
  void _enqueue(SyncEngine e, RemoteChange c) {
    _buffer.add(c);
    if (_drainScheduled) return;
    _drainScheduled = true;
    // A broadcast stream delivers one event per microtask, so the drain
    // waits a whole event-loop turn: by then the burst has all arrived.
    _applying = _applying
        .then((_) => Future<void>.delayed(Duration.zero))
        .then((_) => _drain(e));
  }

  Future<void> _drain(SyncEngine e) async {
    final batch = [..._buffer];
    _buffer.clear();
    _drainScheduled = false;
    // Started in order: each apply reaches its repository's write queue
    // synchronously, so per-node order holds without awaiting between them.
    final failures = await Future.wait([
      for (final c in batch)
        apply(e, c).then<(Object, StackTrace)?>((_) {
          // Only after the write is done: a crash before this replays it.
          e.ack(c.path);
          return null;
        }, onError: (Object error, StackTrace stack) => (error, stack)),
    ]);
    final failed = failures.nonNulls.firstOrNull;
    if (failed != null) Error.throwWithStackTrace(failed.$1, failed.$2);
  }

  /// Replays one merged remote [change] into the wrapped local repository.
  Future<void> apply(SyncEngine engine, RemoteChange change);

  /// Completes once every change received so far has been replayed.
  Future<void> get settled => _applying;

  /// Stops listening for remote changes.
  Future<void> dispose() async {
    await engine;
    await _sub?.cancel();
  }
}
