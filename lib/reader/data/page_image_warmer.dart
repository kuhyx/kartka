import 'dart:async';
import 'dart:typed_data';

import 'package:kartka/core/models/models.dart';

/// Page images fetched ahead for the reader's first pages.
///
/// A MangaFire page costs 0.5-0.9 s on the server, and several at once
/// slow each other (4 at once took up to 1.95 s each). `PageWarmSlot`
/// warms the Continue chapter's first [count] pages here once the details
/// screen loads (the Updates feed warms its first tiles the same way), and
/// the reader loads every image through [load], which serves a warmed one
/// (or joins one still warming) instead of fetching it again.
///
/// One warm fetch runs at a time across all chapters, and a warm waits
/// while the reader fetches a page itself: parallel warms from the Updates
/// feed put the reader's page 4th in line (28fffd0a).
class PageImageWarmer {
  /// A warmer over [_fetch], keeping at most [capacity] images.
  new(this._fetch, {this.capacity = 12, this.count = 3});

  final Future<Uint8List> Function(PageRef page) _fetch;

  /// Images kept; the least recently warmed go first.
  final int capacity;

  /// Pages warmed per chapter, from the page the reader opens on.
  final int count;

  final _kept = <String, Future<Uint8List>>{}; // Insertion-ordered.

  /// Count of reader loads currently in flight.
  int _readerLoads = 0;

  /// Completes when the last reader load finishes; null when none in flight.
  Completer<void>? _idle;

  /// Chain of warm runs; only one executes at a time.
  Future<void> _warmChain = Future<void>.value();

  /// Stores [future] under [url], evicting oldest until capacity holds.
  void _keep(String url, Future<Uint8List> future) {
    _kept[url] = future;
    while (_kept.length > capacity) {
      _kept.remove(_kept.keys.first)?.ignore();
    }
  }

  /// The image of [page]: warmed, warming, or fetched now and kept, so a warm
  /// queued behind it does not fetch it again.
  Future<Uint8List> load(PageRef page) {
    final url = page.imageUrl;
    final kept = _kept[url];
    if (kept != null) return kept;
    _readerLoads++;
    final future = _fetch(page);
    _keep(url, future);
    // On error drop the kept entry so a retry fetches again.
    future
        .then<void>(
          (_) {},
          onError: (Object _) {
            if (identical(_kept[url], future)) _kept.remove(url)?.ignore();
          },
        )
        .ignore();
    future.whenComplete(() {
      if (--_readerLoads == 0) {
        _idle?.complete();
        _idle = null;
      }
    }).ignore();
    return future;
  }

  /// Fetches [count] of [pages] from index [from], one at a time (the
  /// source is rate-limited; the reader's own fetches come first when it
  /// opens). A failure is dropped, so the reader fetches that page again.
  Future<void> warm(List<PageRef> pages, {int from = 0}) {
    final run = _warmChain.then((_) => _warmNow(pages, from));
    _warmChain = run.catchError((Object _) {});
    return run;
  }

  /// Fetches the next [count] pages one by one, waiting for reader loads.
  Future<void> _warmNow(List<PageRef> pages, int from) async {
    for (final page in pages.skip(from).take(count)) {
      final url = page.imageUrl;
      if (_kept.containsKey(url)) continue;
      while (_readerLoads > 0) {
        await (_idle ??= Completer<void>()).future;
        if (_kept.containsKey(url)) break;
      }
      if (_kept.containsKey(url)) continue;
      final future = _fetch(page);
      _keep(url, future);
      try {
        await future;
      } on Object {
        if (identical(_kept[url], future)) _kept.remove(url)?.ignore();
      }
    }
  }
}
