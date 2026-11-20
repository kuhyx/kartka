import 'dart:async';

import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/source/manga_source.dart';
import 'package:kartka/platform/key_value_store.dart';
import 'package:kartka/reader/data/page_source.dart';

/// The source's page lists need a WebView its server cannot run: a known
/// state the reader shows at once (icon and Retry, no text), never a
/// `reader.open` report. The message is for logs only.
class SourceNeedsWebView extends ReaderLoadException {
  /// The error, with its fixed message.
  const new()
    : super(
        'This source needs a WebView the server cannot run. '
        'Retry asks it again.',
      );
}

/// Page lists fetched ahead (the details screen's Continue chapter) or
/// recently, and the sources whose page lists time out on a WebView.
///
/// AllManga's `fetchChapterPages` waits 20 s and fails on every chapter on
/// Suwayomi v2.4.2366 (971debc8, `DOCS-suwayomi.md`). The first such
/// failure marks the source in [KeyValueStore] with no expiry (a marked
/// source is never fetched, so an expiry would lapse and cost another
/// reported 20 s open); Retry asks with `fresh`, and a success clears
/// the mark. Known-broken Suwayomi sources start marked.
class PageListCache {
  /// A cache that keeps its marks in [_kv].
  new(this._kv, {this._now = DateTime.now});

  /// How long a fetched page list is served again.
  static const keep = Duration(minutes: 10);

  /// Key prefix of the marks: `<prefix><sourceId>` = when, UTC ISO-8601.
  static const markPrefix = 'reader.needsWebView.';

  /// Key prefix of the sources that once fetched a page list fine;
  /// `<prefix><sourceId>` = when, UTC ISO-8601.
  static const okPrefix = 'reader.pagesOk.';

  /// Names of Suwayomi sources whose page lists time out on a WebView
  /// on Suwayomi v2.4.2366 (971debc8, `DOCS-suwayomi.md`): they start
  /// marked, with no 20 s first fetch, until one fetch succeeds.
  static const knownBroken = {'AllManga'};

  final KeyValueStore _kv;
  final DateTime Function() _now;
  final _kept = <String, ({List<PageRef> pages, DateTime at})>{};
  final _inFlight = <String, Future<List<PageRef>>>{};

  /// The pages of [chapterUrl] on [source]: in flight, kept, or fetched.
  ///
  /// Throws [SourceNeedsWebView] for a marked source unless [fresh], which
  /// also skips the kept list; a marked source fails at once even while a
  /// fresh fetch of it is in flight.
  Future<List<PageRef>> pages(
    MangaSource source,
    String chapterUrl, {
    bool fresh = false,
  }) async {
    final id = '${source.ref.id}\n$chapterUrl';
    if (!fresh) {
      if (_kept[id] case final k? when _now().difference(k.at) < keep) {
        return k.pages;
      }
      // Before the in-flight join: a Retry's 20 s fetch of a marked source
      // is still running when the user leaves and opens the chapter again,
      // and joining it was a 20 s reader.open on build 591 (971debc8).
      if (await _marked(source)) throw const SourceNeedsWebView();
      if (_inFlight[id] case final running?) return await running;
    }
    return await (_inFlight[id] ??= _fetch(source, chapterUrl, id).whenComplete(
      // A block: returning the removed future would make it wait on itself.
      () {
        unawaited(_inFlight.remove(id));
      },
    ));
  }

  /// Fetches ahead; a failure only marks (see [pages]).
  void warm(MangaSource source, String chapterUrl) =>
      pages(source, chapterUrl).ignore();

  Future<List<PageRef>> _fetch(
    MangaSource source,
    String chapterUrl,
    String id,
  ) async {
    final mark = '$markPrefix${source.ref.id}';
    try {
      final pages = await source.pages(chapterUrl);
      _kept[id] = (pages: pages, at: _now());
      await _kv.remove(mark);
      if (source.ref.origin == SourceOrigin.suwayomi &&
          knownBroken.contains(source.ref.name)) {
        await _kv.set(
          '$okPrefix${source.ref.id}',
          _now().toUtc().toIso8601String(),
        );
      }
      return pages;
    } on Object catch (e) {
      if ('$e'.contains('Timed out waiting for WebView')) {
        await _kv.set(mark, _now().toUtc().toIso8601String());
      }
      rethrow;
    }
  }

  Future<bool> _marked(MangaSource source) async {
    final raw = await _kv.get('$markPrefix${source.ref.id}');
    if (raw != null) return true;
    if (source.ref.origin != SourceOrigin.suwayomi) return false;
    if (!knownBroken.contains(source.ref.name)) return false;
    return await _kv.get('$okPrefix${source.ref.id}') == null;
  }
}
