part of 'reader_screen.dart';

final ButtonStyle _square = IconButton.styleFrom(
  minimumSize: const Size.square(48),
);

/// The reader body: the mode's view, its slots, the overlay and errors.
extension on _ReaderScreenState {
  Widget _reader() {
    final s = _session;
    final item = s.initialItem;
    if (s.mode.isPaged) {
      return PagedReaderView(
        key: ValueKey(s.mode),
        mode: s.mode,
        strip: s.strip,
        initialItem: item,
        slotBuilder: _slot,
        onItemChanged: _onItem,
        controller: _view,
        onTap: _onTap,
      );
    }
    return WebtoonReaderView(
      strip: s.strip,
      initialItem: item,
      slotBuilder: _slot,
      onItemChanged: _onItem,
      controller: _view,
      onTap: _onTap,
    );
  }

  Widget _slot(BuildContext context, StripSlot slot) {
    final s = _session;
    final index = slot.index;
    final flat = slot.flat;
    if (index != null && flat != null) {
      return ReaderPageImage(
        bytes: s.image(flat),
        initial: s.loadedImage(flat),
        pageNumber: index + 1,
        onRetry: s.retry,
        fitWidth: !s.mode.isPaged,
      );
    }
    final forward = !slot.isPreviousChapter;
    final edge = forward ? s.segments.last : s.segments.first;
    final transition = ChapterTransition(
      forward: forward,
      currentName: edge.name,
      targetName: (forward ? s.nextChapter : s.previousChapter)?.name,
      error: forward ? s.nextError : null,
      onRetry: s.retryNext,
      loading: forward && s.nextLoading,
    );
    // A webtoon item has unbounded height; give the transition a screen.
    return s.mode.isPaged
        ? transition
        : SizedBox(
            height: MediaQuery.sizeOf(context).height,
            child: transition,
          );
  }

  /// Plans the decode of the next two pages and the one behind (not the page
  /// on screen: its own image decodes it), at the size [ReaderPageImage]
  /// draws them, once the reader has settled on a page. The pages ahead stay
  /// within the prefetch setting: no extra fetches. Only a move to another
  /// page replans, so the session's other notifications cost nothing.
  void _precacheAround() {
    final s = _session;
    if (s.phase != ReaderPhase.ready) return;
    final current = s.strip.offsetOf(s.segment) + s.page;
    final width = readerDecodeWidth(context);
    if (current == _precacheAt && width == _precacheWidth) return;
    _precacheAt = current;
    _precacheWidth = width;
    final ahead = math.min(2, s.settings.prefetchAhead);
    _precache.schedule([
      for (final flat in [
        for (var i = 1; i <= ahead; i++) current + i,
        current - 1,
      ])
        if (flat >= 0 && flat < s.strip.pageCount) s.image(flat),
    ], width);
  }

  Widget _controls() {
    final s = _session;
    final previous = s.neighbours.previous;
    final next = s.neighbours.next;
    return ReaderControls(
      title: s.chapterName,
      offline: s.offline,
      mode: s.mode,
      page: s.page,
      pageCount: s.pages.length,
      onBack: widget.onExit,
      onMode: (m) => unawaited(s.setMode(m)),
      onFullscreen: _toggleFullscreen,
      onSettings: () => unawaited(_showSettings()),
      onPage: (p) =>
          _view.jumpToItem(s.strip.itemForPage(p, segment: s.segment)),
      onPreviousChapter: previous == null ? null : () => _openChapter(previous),
      onNextChapter: next == null ? null : () => _openChapter(next),
    );
  }

  Widget _failed(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline,
            size: 48,
            color: Theme.of(context).colorScheme.error,
            semanticLabel: 'Could not open the chapter.',
          ),
          if (_session.error case final e?) Text(redactUrlQueries(e)),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton.outlined(
                style: _square,
                onPressed: widget.onExit,
                icon: const Icon(Icons.arrow_back, semanticLabel: 'Back'),
              ),
              const SizedBox(width: AppSpacing.sm),
              IconButton.filled(
                style: _square,
                onPressed: _retryOpen,
                icon: const Icon(Icons.refresh, semanticLabel: 'Retry'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
