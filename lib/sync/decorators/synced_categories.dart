/// [CategoryRepository] that writes through to RTDB `categories/` and
/// `membership/`, and replays merged remote changes into the local one.
library;

import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/repositories/repositories.dart';
import 'package:kartka/sync/decorators/remote_listener.dart';
import 'package:kartka/sync/merge/merge_rules.dart';
import 'package:kartka/sync/rtdb_transport.dart';
import 'package:kartka/sync/sync_engine.dart';
import 'package:kartka/sync/wire/wire.dart';

/// The sync decorator for categories and membership.
class SyncedCategoryRepository
    with RemoteListener
    implements CategoryRepository {
  /// Wraps [inner]; remote changes from [engine] are applied to it.
  SyncedCategoryRepository(this._inner, Future<SyncEngine> engine) {
    listen(engine, {'categories', 'membership'});
  }

  final CategoryRepository _inner;

  @override
  Stream<List<Category>> watch() => _inner.watch();

  @override
  Stream<Map<MangaKey, Set<String>>> watchMembership() =>
      _inner.watchMembership();

  @override
  Future<void> upsert(Category c) async {
    final engine = await this.engine;
    final tick = engine.tick();
    await _inner.upsert(_restamp(c, localStamp(tick)));
    final path = categoryPath(c.id);
    final delta = stampChanges(
      engine.shadow.node(path),
      categoryValues(c),
      tick.toStr(),
    );
    if (delta != null) await engine.write(path, delta);
  }

  @override
  Future<void> setMembership(
    MangaKey key,
    String categoryId,
    // The contract's positional bool (§14).
    // ignore: avoid_positional_boolean_parameters
    bool member,
  ) async {
    final engine = await this.engine;
    await _inner.setMembership(key, categoryId, member);
    await engine.write(membershipPath(key, categoryId), {
      'member': member,
      kHlcField: engine.tick().toStr(),
      'key': key,
    });
  }

  @override
  Future<void> apply(SyncEngine engine, RemoteChange change) async {
    final segments = change.path.split('/');
    if (segments.first == 'categories') {
      final c = categoryFromNode(change.path, change.node);
      if (c == null) return;
      return _inner.upsert(_restamp(c, localStamp(engine.tick())));
    }
    final (key, member) = (change.node['key'], change.node['member']);
    if (key is! String || member is! bool) return;
    await _inner.setMembership(key, rtdbKeyDecode(segments[2]), member);
  }

  static Category _restamp(Category c, DateTime at) => Category(
    id: c.id,
    name: c.name,
    order: c.order,
    updatedAt: at,
    removed: c.removed,
  );
}
