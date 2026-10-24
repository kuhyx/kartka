/// Tracker bindings synced to RTDB `trackers/<mangaKeyHash>/<service>`
/// (contracts §4), through tracking's `BindingStoreDecorator` port.
library;

import 'package:kartka/core/models/models.dart';
import 'package:kartka/sync/decorators/remote_listener.dart';
import 'package:kartka/sync/merge/merge_rules.dart';
import 'package:kartka/sync/merge/tracker_merge.dart';
import 'package:kartka/sync/rtdb_transport.dart';
import 'package:kartka/sync/sync_engine.dart';
import 'package:kartka/tracking/common/binding_store.dart';
import 'package:kartka/tracking/common/track_binding.dart';

/// `trackers/<mangaKeyHash>/<service>`.
String trackerPath(MangaKey key, String service) =>
    'trackers/${mangaKeyHash(key)}/${rtdbKey(service)}';

/// The decorator tracking applies to its binding store.
class SyncBindingDecorator implements BindingStoreDecorator {
  /// Wraps stores around the engine [engine] starts (lazily).
  new(this.engine);

  /// Starts (or returns) the engine.
  final Future<SyncEngine> Function() engine;

  @override
  BindingStore decorate(BindingStore inner) =>
      SyncedBindingStore(inner, engine());
}

/// A [BindingStore] writing through to RTDB; remote bindings are put into
/// the inner store, whose `watch` then emits them mid-session.
class SyncedBindingStore with RemoteListener implements BindingStore {
  /// Wraps `inner`; remote `trackers/` changes from `engine` reach it.
  new(this._inner, Future<SyncEngine> engine) {
    listen(engine, {'trackers'});
  }

  final BindingStore _inner;

  @override
  Future<List<TrackBinding>> all() => _inner.all();

  @override
  Stream<List<TrackBinding>> watch(MangaKey key) => _inner.watch(key);

  @override
  Future<void> put(TrackBinding binding) async {
    final engine = await this.engine;
    await _inner.put(binding);
    if (engine == null) return;
    final path = trackerPath(binding.key, binding.service);
    final old = engine.shadow.node(path);
    // A chapter-count bump keeps the binding's clock; only a (re)bind ticks.
    final same =
        old?['remoteId'] == binding.remoteId && old?['removed'] != true;
    final pushed = binding.lastPushedChapter;
    await engine.write(
      path,
      normalTracker({
        'key': binding.key,
        'service': binding.service,
        'remoteId': binding.remoteId,
        'removed': false,
        kHlcField: same ? old![kHlcField] : engine.tick().toStr(),
        if (pushed != null) kPushedField: {rtdbKey(binding.remoteId): pushed},
      }),
    );
  }

  @override
  Future<void> remove(MangaKey key, String service) async {
    final engine = await this.engine;
    await _inner.remove(key, service);
    if (engine == null) return;
    await engine.write(trackerPath(key, service), {
      'key': key,
      'service': service,
      'removed': true,
      kHlcField: engine.tick().toStr(),
    });
  }

  @override
  Future<void> apply(SyncEngine engine, RemoteChange change) async {
    final n = change.node;
    final (key, service, id) = (n['key'], n['service'], n['remoteId']);
    if (key is! String || service is! String) return;
    if (n['removed'] == true || id is! String) {
      await _inner.remove(key, service);
      return;
    }
    final last = n['lastPushedChapter'];
    await _inner.put(
      TrackBinding(
        key: key,
        service: service,
        remoteId: id,
        lastPushedChapter: last is num ? last.toInt() : null,
      ),
    );
  }
}
