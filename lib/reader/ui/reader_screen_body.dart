part of 'reader_screen.dart';

/// The reader body: the mode's view, its slots, the overlay and errors.
extension on _ReaderScreenState {
  Widget _reader() {
    final s = _session;
    final item = s.strip.itemForPage(s.page);
    if (s.mode.isPaged) {
      return PagedReaderView(
        key: ValueKey(s.mode),
        mode: s.mode,
        strip: s.strip,
        initialItem: item,
        slotBuilder: _slot,
        onItemChanged: s.onItem,
        controller: _view,
        onTap: _onTap,
      );
    }
    return WebtoonReaderView(
      strip: s.strip,
      initialItem: item,
      slotBuilder: _slot,
      onItemChanged: s.onItem,
      controller: _view,
      onTap: _onTap,
    );
  }

  Widget _slot(BuildContext context, StripSlot slot) {
    final s = _session;
    final index = slot.index;
    if (index != null) {
      return ReaderPageImage(
        bytes: s.image(index),
        pageNumber: index + 1,
        onRetry: s.retry,
        fitWidth: !s.mode.isPaged,
      );
    }
    final forward = !slot.isPreviousChapter;
    final target = forward ? s.neighbours.next : s.neighbours.previous;
    final transition = ChapterTransition(
      forward: forward,
      currentName: s.chapterName,
      targetName: target?.name,
      onGo: () => _openChapter(target),
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
      onPage: (p) => _view.jumpToItem(s.strip.itemForPage(p)),
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
