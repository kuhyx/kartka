import 'dart:async';

import 'package:flutter/foundation.dart' hide Category;
import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/redact.dart';
import 'package:kartka/core/source/manga_source.dart';
import 'package:kartka/reader/data/page_source.dart';
import 'package:kartka/reader/data/reader_settings.dart';
import 'package:kartka/reader/logic/chapter_order.dart';
import 'package:kartka/reader/logic/chapter_strip.dart';
import 'package:kartka/reader/logic/page_cache.dart';
import 'package:kartka/reader/logic/prefetch.dart';
import 'package:kartka/reader/logic/progress_recorder.dart';
import 'package:kartka/reader/logic/reader_mode.dart';
import 'package:kartka/reader/state/chapter_segment.dart';
import 'package:kartka/reader/state/reader_deps.dart';

part 'reader_session_advance.dart';

/// Where a session is in its life.
enum ReaderPhase {
  /// Pages are being resolved.
  loading,

  /// Pages are known and can be shown.
  ready,

  /// The chapter could not be opened; see [ReaderSession.error].
  failed,
}

const ChapterNeighbours _noNeighbours = (
  current: null,
  previous: null,
  next: null,
  position: null,
);

/// State of an open reader: the opened chapter plus every chapter the
/// reader advanced into, its position, mode and progress writes.
class ReaderSession extends ChangeNotifier {
  /// A session for [chapterUrl] of [mangaUrl] on [sourceId], opened at its
  /// last page when [startAtEnd] (going back from the next chapter).
  new({
    required this.sourceId,
    required this.mangaUrl,
    required this.chapterUrl,
    required this.deps,
    this.startAtEnd = false,
  });

  /// Source id from the route.
  final String sourceId;

  /// Manga URL from the route.
  final String mangaUrl;

  /// Chapter URL from the route (the first loaded chapter).
  final String chapterUrl;

  /// Injected collaborators.
  final ReaderDeps deps;

  /// Whether to open on the last page instead of the resume position.
  final bool startAtEnd;

  /// The library key of this manga.
  MangaKey get key => mangaKeyOf(sourceId, mangaUrl);

  /// Current phase.
  ReaderPhase phase = ReaderPhase.loading;

  /// Why opening failed, when [phase] is failed.
  String? error;

  /// Global reader settings.
  ReaderSettings settings = const ReaderSettings();

  /// Layout used for this manga.
  ReaderMode mode = const ReaderSettings().defaultMode;

  /// Loaded chapters in reading order; the first is [chapterUrl].
  final List<ChapterSegment> segments = [];

  /// Index into [segments] of the chapter being read.
  int segment = 0;

  /// Current page within that chapter, 0-based.
  int page = 0;

  /// Why the next chapter failed to load, redacted; null when it did not.
  String? nextError;

  List<ChapterInfo> _chapters = const [];
  MangaSource? _source;
  List<PageRef> _flat = const [];
  Future<void>? _nextLoad;
  bool _onTrailing = false;
  PageCache? _cache;
  bool _disposed = false;

  ChapterSegment? get _current => segments.isEmpty ? null : segments[segment];

  /// Pages of the chapter being read.
  List<PageRef> get pages => _current?.pages ?? const [];

  /// Whether [pages] come from a download.
  bool get offline => _current?.offline ?? false;

  /// The chapter being read and its neighbours.
  ChapterNeighbours get neighbours => _current?.neighbours ?? _noNeighbours;

  /// Display name of the chapter being read.
  String get chapterName => _current?.name ?? 'Chapter';

  /// Every loaded page framed by the two edges.
  ChapterStrip get strip => ChapterStrip(
    pageCounts: segments.isEmpty
        ? const [0]
        : [for (final s in segments) s.pages.length],
  );

  /// The list item for the current page when a view first mounts.
  int get initialItem => strip.itemForPage(page, segment: segment);

  /// The chapter after the last loaded one, or null at the end.
  ChapterInfo? get nextChapter =>
      segments.isEmpty ? null : segments.last.neighbours.next;

  /// The chapter before the first loaded one, or null at the start.
  ChapterInfo? get previousChapter =>
      segments.isEmpty ? null : segments.first.neighbours.previous;

  /// Whether the next chapter's pages are being fetched.
  bool get nextLoading => _nextLoad != null;

  /// Resolves settings, chapter list, pages and the start position.
  Future<void> open() async {
    settings = await deps.prefs.settings();
    mode = await deps.prefs.effectiveMode(key);
    final source = _source = await deps.findSource(sourceId);
    _chapters = await _chapterList(source);
    final ChapterPages loaded;
    try {
      loaded = await loadChapterPages(
        key: key,
        chapterUrl: chapterUrl,
        downloads: deps.downloads,
        source: source,
      );
    } on ReaderLoadException catch (e) {
      return _fail(e.message);
    } on Object catch (e) {
      return _fail('$e');
    }
    final last = loaded.pages.length - 1;
    page = startAtEnd ? (last < 0 ? 0 : last) : await _resumePage(last);
    // The reader may have been left while this was loading.
    if (_disposed) return;
    _cache = PageCache(fetch: (i) => deps.loadImage(_flat[i]));
    _add(chapterUrl, loaded, landing: startAtEnd ? page : null);
    phase = ReaderPhase.ready;
    _prefetch();
    _maybeLoadNext();
    notifyListeners();
  }

  /// The bytes of the page at [flat] among every loaded page.
  Future<Uint8List> image(int flat) => _cache!.get(flat);

  /// Rebuilds so failed pages fetch again.
  void retry() => notifyListeners();

  /// Tries the failed next chapter again.
  void retryNext() {
    nextError = null;
    _maybeLoadNext(force: true);
    notifyListeners();
  }

  /// Reports that the view now shows list item [item].
  void onItem(int item) {
    if (segments.isEmpty) return;
    final slot = strip.slotAt(item);
    _onTrailing = !slot.isPage && !slot.isPreviousChapter;
    if (slot.isPreviousChapter) {
      segment = 0;
      page = 0;
    } else {
      segment = slot.isPage ? slot.segment : segments.length - 1;
      page = slot.index ?? segments.last.pages.length - 1;
      segments[segment].recorder.onPage(page);
    }
    _prefetch();
    _maybeLoadNext();
    notifyListeners();
  }

  /// Switches this manga to [m] and remembers it.
  Future<void> setMode(ReaderMode m) async {
    mode = m;
    notifyListeners();
    await deps.prefs.setModeFor(key, m);
  }

  /// Replaces and stores the global settings.
  Future<void> updateSettings(ReaderSettings s) async {
    settings = s;
    _prefetch();
    notifyListeners();
    await deps.prefs.saveSettings(s);
  }

  @override
  void notifyListeners() {
    // open() and the async loads outlive a reader that was left early.
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final s in segments) {
      s.recorder.dispose();
    }
    _cache?.clear();
    super.dispose();
  }
}
