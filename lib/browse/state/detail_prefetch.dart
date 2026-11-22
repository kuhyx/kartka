import 'dart:async';

import 'package:kartka/browse/browse_scope.dart';
import 'package:kartka/core/models/models.dart';

/// A manga's details and chapter list, fetched ahead of its detail screen,
/// plus the tile it was started from (its title and cover show at once).
class PrefetchedDetail {
  /// Creates the entry; [details] and [chapters] are already running.
  const new(this.tile, this.details, this.chapters, this.at);

  /// The tile hovered or pressed.
  final MangaSummary tile;

  /// The source's details.
  final Future<MangaDetails> details;

  /// A fresh chapter list (`ChapterStore.load(refresh: true)`).
  final Future<List<ChapterInfo>> chapters;

  /// When the fetches started.
  final DateTime at;
}

/// Starts a manga's detail fetches when its tile is hovered or pressed, so
/// the detail screen opens on work already under way (9f7cad2f: Suwayomi's
/// MangaFire took up to 1.4 s each for details and chapters).
class DetailPrefetch {
  /// Keeps the [limit] newest entries for [keep] each.
  new({
    this.keep = const Duration(minutes: 2),
    this.limit = 6,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// How long a fetch stays fresh enough to show.
  final Duration keep;

  /// How many tiles stay warm (a mouse crossing the grid hovers several).
  final int limit;

  final DateTime Function() _clock;
  final _entries = <MangaKey, PrefetchedDetail>{};

  /// Starts [manga]'s details and chapter list unless they are already
  /// running; a source not listed (yet) starts nothing.
  void warm(BrowseDeps deps, MangaSummary manga) {
    final key = manga.key;
    if (_fresh(_entries[key]) != null) return;
    final source = deps.sources.byId(manga.sourceId);
    if (source == null) return;
    _entries.remove(key);
    _entries[key] = PrefetchedDetail(
      manga,
      source.details(manga.url)..ignore(),
      deps.chapters.load(key, refresh: true)..ignore(),
      _clock(),
    );
    while (_entries.length > limit) {
      _entries.remove(_entries.keys.first);
    }
  }

  /// [key]'s entry, once, while fresh.
  PrefetchedDetail? take(MangaKey key) => _fresh(_entries.remove(key));

  PrefetchedDetail? _fresh(PrefetchedDetail? entry) =>
      entry != null && _clock().difference(entry.at) < keep ? entry : null;
}
