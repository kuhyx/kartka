import 'dart:async';
import 'dart:typed_data';

import 'package:kartka/core/models/models.dart';

/// Page images fetched ahead for the reader's first pages.
///
/// A MangaFire page costs 0.5-0.9 s on the server and two at once are no
/// faster, so the first page after a chapter opened was a reported
/// `reader.page` wait (28fffd0a). `PageWarmSlot` warms the Continue
/// chapter's first [count] pages here once the details screen loads, and
/// the reader loads every image through [load], which serves a warmed one
/// (or joins one still warming) instead of fetching it again.
class PageImageWarmer {
  /// A warmer over [_fetch], keeping at most [capacity] images.
  new(this._fetch, {this.capacity = 12, this.count = 3});

  final Future<Uint8List> Function(PageRef page) _fetch;

  /// Images kept; the least recently warmed go first.
  final int capacity;

  /// Pages warmed per chapter, from the page the reader opens on.
  final int count;

  final _kept = <String, Future<Uint8List>>{}; // Insertion-ordered.

  /// The image of [page]: warmed, warming, or fetched now.
  Future<Uint8List> load(PageRef page) => _kept[page.imageUrl] ?? _fetch(page);

  /// Fetches [count] of [pages] from index [from], one at a time (the
  /// source is rate-limited; the reader's own fetches come first when it
  /// opens). A failure is dropped, so the reader fetches that page again.
  Future<void> warm(List<PageRef> pages, {int from = 0}) async {
    for (final page in pages.skip(from).take(count)) {
      final url = page.imageUrl;
      if (_kept.containsKey(url)) continue;
      final future = _fetch(page);
      _kept[url] = future;
      while (_kept.length > capacity) {
        _kept.remove(_kept.keys.first)?.ignore();
      }
      try {
        await future;
      } on Object {
        if (identical(_kept[url], future)) _kept.remove(url)?.ignore();
      }
    }
  }
}
