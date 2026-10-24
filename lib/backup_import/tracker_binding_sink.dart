import 'dart:convert';

import 'package:kartka/core/models/models.dart';
import 'package:kartka/platform/key_value_store.dart';

/// Where imported tracker bindings go. Owned by backup_import; the tracking
/// part can supply its own implementation as a registry service (backed by
/// sync path `trackers/<mangaKeyHash>/<service>`), otherwise
/// [KvTrackerBindingStore] keeps them so nothing is lost.
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

/// Default sink: a plain [KeyValueStore] record per (manga, service).
class KvTrackerBindingStore implements TrackerBindingSink {
  /// Creates a store over [kv].
  const KvTrackerBindingStore(this.kv);

  /// Key prefix, also usable to enumerate bindings.
  static const String prefix = 'tracker-binding/';

  /// Backing store.
  final KeyValueStore kv;

  @override
  Future<bool> bind(
    MangaKey key,
    String service,
    String remoteId, {
    int lastPushedChapter = 0,
  }) async {
    final storageKey = '$prefix${mangaKeyHash(key)}/$service';
    final raw = await kv.get(storageKey);
    if (raw != null) {
      final old = jsonDecode(raw) as Map<String, Object?>;
      final oldChapter = old['lastPushedChapter']! as int;
      if (old['remoteId'] != remoteId || oldChapter >= lastPushedChapter) {
        return false;
      }
    }
    await kv.set(
      storageKey,
      jsonEncode({
        'key': key,
        'remoteId': remoteId,
        'lastPushedChapter': lastPushedChapter,
      }),
    );
    return true;
  }
}
