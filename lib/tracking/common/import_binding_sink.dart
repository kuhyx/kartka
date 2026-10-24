import 'package:collection/collection.dart';
import 'package:kartka/backup_import/tracker_binding_sink.dart';
import 'package:kartka/core/models/manga_key.dart';
import 'package:kartka/tracking/common/track_binding.dart';
import 'package:kartka/tracking/common/tracking_service.dart';

/// [TrackerBindingSink] for the .tachibk import, over the tracking bindings.
///
/// Idempotent: an existing binding to another remote id wins, and the
/// imported remote count only ever raises `lastPushedChapter`.
class ImportBindingSink implements TrackerBindingSink {
  /// Creates the sink writing through [_service].
  new(this._service);

  final TrackingService _service;

  @override
  Future<bool> bind(
    MangaKey key,
    String service,
    String remoteId, {
    int lastPushedChapter = 0,
  }) async {
    final store = _service.bindings;
    final old = (await store.all()).firstWhereOrNull(
      (b) => b.key == key && b.service == service,
    );
    if (old != null && old.remoteId != remoteId) return false;
    final count = lastPushedChapter > 0 ? lastPushedChapter : null;
    final have = old?.lastPushedChapter;
    if (old != null && (count == null || (have != null && have >= count))) {
      return false;
    }
    await store.put(
      TrackBinding(
        key: key,
        service: service,
        remoteId: remoteId,
        lastPushedChapter: count,
      ),
    );
    _service.follow(key);
    return true;
  }
}
