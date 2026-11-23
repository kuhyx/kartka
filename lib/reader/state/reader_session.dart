import 'dart:async';

import 'package:flutter/foundation.dart' hide Category;
import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/redact.dart';
import 'package:kartka/core/source/manga_source.dart';
import 'package:kartka/reader/data/page_list_cache.dart';
import 'package:kartka/reader/data/page_source.dart';
import 'package:kartka/reader/data/reader_settings.dart';
import 'package:kartka/reader/logic/chapter_order.dart';
import 'package:kartka/reader/logic/chapter_strip.dart';
import 'package:kartka/reader/logic/first_images_probe.dart';
import 'package:kartka/reader/logic/page_cache.dart';
import 'package:kartka/reader/logic/page_wait_probe.dart';
import 'package:kartka/reader/logic/prefetch.dart';
import 'package:kartka/reader/logic/progress_recorder.dart';
import 'package:kartka/reader/logic/reader_mode.dart';
import 'package:kartka/reader/state/chapter_segment.dart';
import 'package:kartka/reader/state/reader_deps.dart';

part 'reader_session_ahead.dart';
part 'reader_session_advance.dart';
part 'reader_session_open.dart';

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
    this.fresh = false,
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

  /// Whether the open asks the source even for a kept or marked page list
  /// (the failed screen's Retry).
  final bool fresh;

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
  Future<void>? _listReady;
  MangaSource? _source;
  List<PageRef> _flat = const [];
  late final _pageWait = PageWaitProbe(now: deps.now, onSlow: _pageSlow);
  Future<void>? _nextLoad;
  bool _onTrailing = false;
  bool _listPending = false;
  final _EdgeWait _edge = _EdgeWait();
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

  /// Whether the view's current item is the slot after the last page.
  bool get onTrailing => _onTrailing;

  /// Whether the next chapter's pages, or the chapter list that names it,
  /// are being fetched (a stored list that ends here is not the end yet).
  bool get nextLoading => _nextLoad != null || _listPending;

  /// Whether the chapter list that names the previous chapter is on its
  /// way: the previous slot is unknown, not absent.
  bool get previousLoading => _listPending;

  /// Resolves settings, pages and the start position. The chapter list
  /// does not hold the first page; it names the neighbours when it comes.
  Future<void> open() => _openChapter();

  /// The bytes of the page at [flat] among every loaded page, fetched in
  /// the queue's turn, never beside it (28fffd0a). A failure shown here
  /// (the page's Retry) is logged as `reader.page`; a failed background
  /// prefetch is not. The current page's wait is timed (`PageWaitProbe`).
  Future<Uint8List> image(int flat) {
    final bytes = _cache!.waitFor(flat);
    final shown = flat == strip.offsetOf(segment) + page;
    if (shown && _cache!.peek(flat) == null) _pageWait.asked(flat, bytes);
    return bytes.onError<Object>(_pageFailed);
  }

  /// The bytes of the page at [flat] if they have arrived, else null.
  Uint8List? loadedImage(int flat) => _cache?.peek(flat);

  /// Rebuilds so failed pages fetch again.
  void retry() => notifyListeners();

  /// Tries the failed next chapter again.
  void retryNext() {
    if (_onTrailing) _edgeMoved(trailing: true);
    nextError = null;
    _maybeLoadNext();
    notifyListeners();
  }

  /// Reports that the view now shows list item [item].
  void onItem(int item) {
    if (segments.isEmpty) return;
    final slot = strip.slotAt(item);
    final trailing = !slot.isPage && !slot.isPreviousChapter;
    if (trailing != _onTrailing) _edgeMoved(trailing: trailing);
    _onTrailing = trailing;
    if (slot.isPreviousChapter) {
      segment = 0;
      page = 0;
    } else {
      final from = segment;
      segment = slot.isPage ? slot.segment : segments.length - 1;
      // A fast scroll can skip a short last page: chapters left behind
      // going forward were read through, so their recorders see the end.
      for (var k = from; k < segment; k++) {
        segments[k].recorder.onPage(segments[k].pages.length - 1);
      }
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
