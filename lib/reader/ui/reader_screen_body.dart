part of 'reader_screen.dart';

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
    );
    // A webtoon item has unbounded height; give the transition a screen.
    return s.mode.isPaged
        ? transition
        : SizedBox(
            height: MediaQuery.sizeOf(context).height,
            child: transition,
          );
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
          Text(
            redactUrlQueries(_session.error ?? 'Could not open the chapter.'),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton(
                onPressed: widget.onExit,
                child: const Text('Back'),
              ),
              const SizedBox(width: AppSpacing.sm),
              FilledButton(onPressed: _retryOpen, child: const Text('Retry')),
            ],
          ),
        ],
      ),
    ),
  );
}
