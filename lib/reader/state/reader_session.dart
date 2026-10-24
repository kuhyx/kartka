import 'dart:async';

import 'package:flutter/foundation.dart' hide Category;
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/source/manga_source.dart';
import 'package:kartka/reader/data/page_source.dart';
import 'package:kartka/reader/data/reader_settings.dart';
import 'package:kartka/reader/logic/chapter_order.dart';
import 'package:kartka/reader/logic/chapter_strip.dart';
import 'package:kartka/reader/logic/page_cache.dart';
import 'package:kartka/reader/logic/prefetch.dart';
import 'package:kartka/reader/logic/progress_recorder.dart';
import 'package:kartka/reader/logic/reader_mode.dart';
import 'package:kartka/reader/state/reader_deps.dart';

/// Where a session is in its life.
enum ReaderPhase {
  /// Pages are being resolved.
  loading,

  /// Pages are known and can be shown.
  ready,

  /// The chapter could not be opened; see [ReaderSession.error].
  failed,
}

/// State of one open chapter: pages, position, mode and progress writes.
class ReaderSession extends ChangeNotifier {
  /// A session for [chapterUrl] of [mangaUrl] on [sourceId].
  new({
    required this.sourceId,
    required this.mangaUrl,
    required this.chapterUrl,
    required this.deps,
  });

  /// Source id from the route.
  final String sourceId;

  /// Manga URL from the route.
  final String mangaUrl;

  /// Chapter URL from the route.
  final String chapterUrl;

  /// Injected collaborators.
  final ReaderDeps deps;

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

  /// Pages of the chapter in order.
  List<PageRef> pages = const [];

  /// Whether [pages] come from a download.
  bool offline = false;

  /// This chapter and its neighbours, when the chapter list loaded.
  ChapterNeighbours neighbours = (
    current: null,
    previous: null,
    next: null,
    position: null,
  );

  /// Current page, 0-based.
  int page = 0;

  PageCache? _cache;
  ProgressRecorder? _recorder;
  bool _disposed = false;

  /// Pages framed by chapter transitions.
  ChapterStrip get strip => ChapterStrip(pageCount: pages.length);

  /// The list item for [page] when the view first mounts.
  int get initialItem => strip.itemForPage(page);

  /// Display name of the chapter.
  String get chapterName => neighbours.current?.name ?? 'Chapter';

  /// Resolves settings, chapter list, pages and the resume position.
  Future<void> open() async {
    settings = await deps.prefs.settings();
    mode = await deps.prefs.effectiveMode(key);
    final source = await deps.findSource(sourceId);
    neighbours = await _neighbours(source);
    try {
      final loaded = await loadChapterPages(
        key: key,
        chapterUrl: chapterUrl,
        downloads: deps.downloads,
        source: source,
      );
      pages = loaded.pages;
      offline = loaded.offline;
    } on ReaderLoadException catch (e) {
      return _fail(e.message);
    } on Object catch (e) {
      return _fail('$e');
    }
    page = await _resumePage();
    // The reader may have been left while this was loading.
    if (_disposed) return;
    _cache = PageCache(fetch: (i) => deps.loadImage(pages[i]));
    _recorder = ProgressRecorder(
      pageCount: pages.length,
      record: _record,
      markRead: () async => await deps.progress?.markRead(key, chapterUrl),
    );
    phase = ReaderPhase.ready;
    _prefetch();
    notifyListeners();
  }

  void _fail(String message) {
    error = message;
    phase = ReaderPhase.failed;
    notifyListeners();
  }

  Future<ChapterNeighbours> _neighbours(MangaSource? source) async {
    try {
      final list = await source?.chapters(mangaUrl) ?? const <ChapterInfo>[];
      return neighboursOf(list, chapterUrl);
    } on Object {
      // Offline reading must not depend on the chapter list.
      return neighboursOf(const [], chapterUrl);
    }
  }

  Future<int> _resumePage() async {
    final progress = deps.progress;
    if (progress == null) return 0;
    final saved = await progress
        .watch(key)
        .first
        .timeout(const Duration(seconds: 2), onTimeout: () => null);
    if (saved == null || saved.chapterUrl != chapterUrl) return 0;
    return saved.page < pages.length - 1 ? saved.page : 0;
  }

  Future<void> _record(int page) async {
    final number = progressNumber(neighbours.current, neighbours.position);
    // Unknown chapter number (offline): only markRead may land.
    if (number == null) return;
    await deps.progress?.record(
      ReadingProgress(
        key: key,
        chapterUrl: chapterUrl,
        chapterNumber: number,
        page: page,
        readAt: deps.now(),
      ),
    );
  }

  /// The bytes of page [index].
  Future<Uint8List> image(int index) => _cache!.get(index);

  /// Rebuilds so failed pages fetch again.
  void retry() => notifyListeners();

  /// Reports that the view now shows list item [item].
  void onItem(int item) {
    final recorder = _recorder;
    if (recorder == null) return;
    final slot = strip.slotAt(item);
    if (slot.isPreviousChapter) {
      page = 0;
    } else {
      page = slot.index ?? pages.length - 1;
      recorder.onPage(page);
    }
    _prefetch();
    notifyListeners();
  }

  void _prefetch() {
    final total = pages.length;
    final ahead = settings.prefetchAhead;
    _cache
      ?..prefetch([
        if (total > 0) page,
        ...prefetchIndices(current: page, total: total, ahead: ahead),
      ])
      ..retain(retainWindow(current: page, total: total, ahead: ahead));
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
    // open() and the async setters outlive a reader that was left early.
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _recorder?.dispose();
    _cache?.clear();
    super.dispose();
  }
}
