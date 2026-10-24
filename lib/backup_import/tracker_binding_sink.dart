import 'package:kartka/core/models/models.dart';

/// Where imported tracker bindings go. Owned by backup_import; the tracking
/// part supplies an implementation as a `KartkaFeature.services` entry (backed
/// by its binding store, sync path `trackers/<mangaKeyHash>/<service>`).
/// Without one the import skips bindings; re-running it once tracking is
/// installed binds them, because the import is idempotent.
abstract interface class TrackerBindingSink {
  /// Binds [key] to [remoteId] on [service] (`anilist` | `mal`).
  ///
  /// Must be idempotent and never lower `lastPushedChapter`. An existing
  /// binding to a different remote id wins over the import. Returns true when
  /// something was written.
  Future<bool> bind(
    MangaKey key,
    String service,
    String remoteId, {
    int lastPushedChapter = 0,
  });
}
