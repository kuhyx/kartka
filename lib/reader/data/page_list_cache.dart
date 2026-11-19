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
/// failure marks the source in [KeyValueStore] for [brokenFor], so later
/// opens of any of its chapters fail at once, also after a restart. Retry
/// asks with `fresh`, and a success clears the mark.
class PageListCache {
  /// A cache that keeps its marks in [_kv].
  new(this._kv, {this._now = DateTime.now});

  /// How long a fetched page list is served again.
  static const keep = Duration(minutes: 10);

  /// How long a WebView timeout keeps its source marked.
  static const brokenFor = Duration(days: 7);

  /// Key prefix of the marks: `<prefix><sourceId>` = expiry, UTC ISO-8601.
  static const markPrefix = 'reader.needsWebView.';

  final KeyValueStore _kv;
  final DateTime Function() _now;
  final _kept = <String, ({List<PageRef> pages, DateTime at})>{};
  final _inFlight = <String, Future<List<PageRef>>>{};

  /// The pages of [chapterUrl] on [source]: in flight, kept, or fetched.
  ///
  /// Throws [SourceNeedsWebView] for a marked source unless [fresh], which
  /// also skips the kept list.
  Future<List<PageRef>> pages(
    MangaSource source,
    String chapterUrl, {
    bool fresh = false,
  }) async {
    final id = '${source.ref.id}\n$chapterUrl';
    if (!fresh) {
      if (_inFlight[id] case final running?) return await running;
      if (_kept[id] case final k? when _now().difference(k.at) < keep) {
        return k.pages;
      }
      if (await _marked(source.ref.id)) throw const SourceNeedsWebView();
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
      return pages;
    } on Object catch (e) {
      if ('$e'.contains('Timed out waiting for WebView')) {
        await _kv.set(mark, _now().add(brokenFor).toUtc().toIso8601String());
      }
      rethrow;
    }
  }

  Future<bool> _marked(String sourceId) async {
    final raw = await _kv.get('$markPrefix$sourceId');
    final until = raw == null ? null : DateTime.tryParse(raw);
    return until != null && _now().isBefore(until);
  }
}
