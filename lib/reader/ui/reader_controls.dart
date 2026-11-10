import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/reader/logic/reader_mode.dart';
import 'package:kartka/reader/ui/page_slider.dart';

/// The overlay shown on a centre tap: top bar and bottom page bar.
class ReaderControls extends StatelessWidget {
  /// Controls for the chapter called [title].
  const new({
    required this.title,
    required this.offline,
    required this.mode,
    required this.page,
    required this.pageCount,
    required this.onBack,
    required this.onMode,
    required this.onFullscreen,
    required this.onSettings,
    required this.onPage,
    this.onPreviousChapter,
    this.onNextChapter,
    super.key,
  });

  /// Chapter name.
  final String title;

  /// Whether the chapter is read from a download.
  final bool offline;

  /// Current reading mode.
  final ReaderMode mode;

  /// Current page, 0-based.
  final int page;

  /// Pages in the chapter.
  final int pageCount;

  /// Leaves the reader.
  final VoidCallback onBack;

  /// Picks another reading mode.
  final ValueChanged<ReaderMode> onMode;

  /// Toggles fullscreen.
  final VoidCallback onFullscreen;

  /// Opens reader settings.
  final VoidCallback onSettings;

  /// Jumps to a page.
  final ValueChanged<int> onPage;

  /// Opens the previous chapter; null when there is none.
  final VoidCallback? onPreviousChapter;

  /// Opens the next chapter; null when there is none.
  final VoidCallback? onNextChapter;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bar = scheme.surfaceContainerHighest.withValues(alpha: 0.94);
    return Column(
      children: [
        Material(
          color: bar,
          child: SafeArea(
            bottom: false,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, semanticLabel: 'Back'),
                  onPressed: onBack,
                ),
                Expanded(child: _title(context)),
                PopupMenuButton<ReaderMode>(
                  // Empty: the default "Show menu" tooltip paints words.
                  tooltip: '',
                  icon: Icon(mode.icon, semanticLabel: 'Reading mode'),
                  initialValue: mode,
                  onSelected: onMode,
                  itemBuilder: (context) => [
                    for (final m in ReaderMode.values)
                      PopupMenuItem(
                        value: m,
                        child: Icon(m.icon, semanticLabel: m.label),
                      ),
                  ],
                ),
                IconButton(
                  icon: const Icon(
                    Icons.fullscreen,
                    semanticLabel: 'Fullscreen',
                  ),
                  onPressed: onFullscreen,
                ),
                IconButton(
                  icon: const Icon(
                    Icons.tune,
                    semanticLabel: 'Reader settings',
                  ),
                  onPressed: onSettings,
                ),
              ],
            ),
          ),
        ),
        const Spacer(),
        Material(
          color: bar,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.skip_previous,
                      semanticLabel: 'Previous chapter',
                    ),
                    onPressed: onPreviousChapter,
                  ),
                  Expanded(
                    child: PageSlider(
                      page: page,
                      pageCount: pageCount,
                      rightToLeft: mode.reversed,
                      onChanged: onPage,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.skip_next,
                      semanticLabel: 'Next chapter',
                    ),
                    onPressed: onNextChapter,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _title(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      spacing: AppSpacing.xs,
      children: [
        Flexible(
          child: Text(title, style: theme.textTheme.titleMedium, maxLines: 1),
        ),
        if (offline)
          Icon(
            Icons.download_done,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
            semanticLabel: 'Downloaded',
          ),
      ],
    );
  }
}
