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

  /// Subscribes to [engine]'s changes under [namespaces] once it is ready.
  void listen(Future<SyncEngine> engine, Set<String> namespaces) {
    this.engine = engine.then<SyncEngine?>(
      (e) => e,
      onError: (Object _) => null,
    );
    unawaited(
      this.engine.then((e) {
        if (e == null) return;
        _sub = e.remoteChanges
            .where((c) => namespaces.contains(c.path.split('/').first))
            // Serial, so a later change for one node never lands first.
            .listen((c) => _applying = _applying.then((_) => apply(e, c)));
      }),
    );
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
