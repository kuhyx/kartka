import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kartka/browse/state/manga_detail_controller.dart';
import 'package:kartka/core/models/models.dart';

/// The download control of one chapter row, following its live state:
/// download (or retry) when absent or failed, cancel while queued or
/// downloading, delete once downloaded. Cancel and delete need the
/// downloads part's `DownloadService`; without it those states show a
/// plain status icon instead.
class ChapterDownloadButton extends StatefulWidget {
  /// Creates the control; key it by chapter url so a recycled row never
  /// keeps another chapter's subscription.
  const new({required this.controller, required this.chapter, super.key});

  /// Detail state (actions and download states).
  final MangaDetailController controller;

  /// The chapter controlled.
  final ChapterInfo chapter;

  @override
  State<ChapterDownloadButton> createState() => _ChapterDownloadButtonState();
}

class _ChapterDownloadButtonState extends State<ChapterDownloadButton> {
  // Subscribed once per chapter, not on every row rebuild.
  late final Stream<DownloadState>? _state = widget.controller.downloadState(
    widget.chapter.url,
  );

  @override
  Widget build(BuildContext context) => StreamBuilder<DownloadState>(
    stream: _state,
    builder: (context, snap) => switch (snap.data) {
      null => const SizedBox.square(dimension: kMinInteractiveDimension),
      final s => _forState(context, s),
    },
  );

  Widget _forState(BuildContext context, DownloadState state) {
    final c = widget.controller;
    final chapter = widget.chapter;
    final manage = c.canManageDownloads;
    return switch (state.status) {
      DownloadStatus.none || DownloadStatus.failed => IconButton(
        tooltip: state.status == DownloadStatus.failed
            ? 'Download failed: retry'
            : 'Download',
        icon: Icon(
          state.status == DownloadStatus.failed
              ? Icons.error_outline
              : Icons.download_outlined,
        ),
        onPressed: () => unawaited(c.download([chapter])),
      ),
      DownloadStatus.queued ||
      DownloadStatus.downloading when manage => IconButton(
        tooltip: 'Cancel download',
        icon: const Icon(Icons.cancel_outlined),
        onPressed: () => unawaited(c.cancelDownload(chapter)),
      ),
      DownloadStatus.queued ||
      DownloadStatus.downloading => const _Status('Queued', Icons.downloading),
      DownloadStatus.done when manage => IconButton(
        tooltip: 'Delete download',
        icon: const Icon(Icons.delete_outline),
        onPressed: () => unawaited(c.deleteDownload(chapter)),
      ),
      DownloadStatus.done => const _Status('Downloaded', Icons.download_done),
    };
  }
}

/// A non-interactive state icon with a tooltip, sized like an IconButton.
class _Status extends StatelessWidget {
  const new(this.label, this.icon);

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: SizedBox.square(
      dimension: kMinInteractiveDimension,
      child: Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
}
