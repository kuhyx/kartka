import 'dart:convert';

import 'package:kartka/core/models/models.dart';
import 'package:kartka/platform/key_value_store.dart';

/// The last fetched details of each library manga (authors, status,
/// description, cover url), so a reopen renders the whole header at once
/// instead of "unknown" until the source answers. Device-local, not
/// synced: it is a cache, refreshed by every detail fetch.
class DetailStore {
  /// Persists to [_kv]; with none, nothing is kept.
  const new(this._kv);

  final KeyValueStore? _kv;

  static String _kvKey(MangaKey key) => 'browse.details.${mangaKeyHash(key)}';

  /// The stored details of [key], or null (none, or corrupt).
  Future<MangaDetails?> read(MangaKey key) async {
    final raw = await _kv?.get(_kvKey(key));
    if (raw == null) return null;
    try {
      return MangaDetails.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } on Object {
      return null; // Corrupt: behave as never fetched; the next fetch fixes it.
    }
  }

  /// Stores [details] as the last fetched for [key].
  Future<void> write(MangaKey key, MangaDetails details) async =>
      await _kv?.set(_kvKey(key), jsonEncode(details.toJson()));

  /// Drops the stored details of [key].
  Future<void> remove(MangaKey key) async => await _kv?.remove(_kvKey(key));
}
