import 'dart:async';

import 'package:kartka/browse/state/chapter_order.dart';
import 'package:kartka/browse/state/chapter_store.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/updates/chapter_update_checker.dart';

/// Browse's [ChapterUpdateChecker] over its persistent [ChapterStore]: the
/// stored list is the store's cache (or its key-value copy after a
/// restart), and the fetch goes through `ChapterStore.load(refresh: true)`,
/// which also persists it.
class StoreChapterUpdateChecker implements ChapterUpdateChecker {
  /// Creates the checker over [_store].
  new(this._store);

  final ChapterStore _store;
  final Map<MangaKey, Future<UpdateResult>> _inFlight = {};

  @override
  Future<UpdateResult> check(MangaKey key) =>
      _inFlight[key] ??= _checkOnce(key);

  // Async, so the entry is set before it is removed. The removed future is
  // this one: awaiting it here would never complete.
  Future<UpdateResult> _checkOnce(MangaKey key) async {
    try {
      return await _check(key);
    } finally {
      unawaited(_inFlight.remove(key));
    }
  }

  Future<UpdateResult> _check(MangaKey key) async {
    try {
      final before = await _store.stored(key);
      final chapters = await _store.load(key, refresh: true);
      final known = {...?before?.map((c) => c.url)};
      return UpdateFound(
        key,
        chapters: chapters,
        added: before == null
            ? const []
            : readingOrder([
                for (final c in chapters)
                  if (!known.contains(c.url)) c,
              ]),
        firstCheck: before == null,
      );
    } on Object catch (e, s) {
      return UpdateFailed(key, e, s);
    }
  }
}
