import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/source/manga_source.dart';
import 'package:kartka/platform/key_value_store.dart';

/// Display titles of downloaded manga the library does not know (removed,
/// migrated to another source, or downloaded straight from Browse), which
/// otherwise show as their raw manga url.
///
/// Asks the owning source's `details()` once and keeps the answer in the kv
/// store, so the Downloads screen names them offline on later launches.
class DownloadTitles {
  /// Resolves through [findSource], caching in [kv].
  new({required this.kv, required this.findSource});

  /// Where resolved titles persist.
  final KeyValueStore kv;

  /// Finds the source of a source id (the downloads `SourceDirectory`).
  final Future<MangaSource?> Function(String sourceId) findSource;

  final Map<MangaKey, Future<String?>> _pending = {};

  /// The title of [key], or null when it cannot be found right now (a
  /// failure is forgotten, so the next call tries again).
  Future<String?> title(MangaKey key) => _pending[key] ??= _remembered(key);

  Future<String?> _remembered(MangaKey key) async {
    final title = await _resolve(key);
    if (title == null) _pending.remove(key)?.ignore();
    return title;
  }

  Future<String?> _resolve(MangaKey key) async {
    final kvKey = 'downloads.title.${mangaKeyHash(key)}';
    final stored = await kv.get(kvKey);
    if (stored != null) return stored;
    try {
      final (sourceId, url) = splitMangaKey(key);
      final source = await findSource(sourceId);
      if (source == null) return null;
      final title = (await source.details(url)).title;
      await kv.set(kvKey, title);
      return title;
    } on Object {
      return null;
    }
  }
}
