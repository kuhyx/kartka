import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/downloads/download_service.dart';
import 'package:kartka/downloads/downloads_snapshot.dart';
import 'package:kartka/downloads/ui/format.dart';
import 'package:kartka/downloads/ui/offline_manga_tile.dart';
import 'package:kartka/downloads/ui/queue_tile.dart';

/// More → Downloads: the queue with progress, pause/resume, cancel, retry,
/// and the offline chapters with their storage use.
class DownloadsScreen extends StatefulWidget {
  /// Creates the screen.
  const new({
    required this.service,
    required this.titles,
    this.onOpen,
    this.resolveTitle,
    super.key,
  });

  /// The download service.
  final DownloadService service;

  /// Manga titles by key (from the library), for display.
  final Stream<Map<MangaKey, String>> titles;

  /// Called once when the screen opens (the auto-download check).
  final VoidCallback? onOpen;

  /// Title of a manga missing from [titles] (`DownloadTitles.title`);
  /// null for none. Until it answers, the manga url is shown.
  final Future<String?> Function(MangaKey key)? resolveTitle;

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  late final Stream<DownloadsSnapshot> _snapshots = widget.service.watchAll();
  late final Stream<Map<MangaKey, String>> _titles = widget.titles;
  final Map<MangaKey, String> _resolved = {};
  final Set<MangaKey> _asked = {};

  @override
  void initState() {
    super.initState();
    widget.onOpen?.call();
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<Map<MangaKey, String>>(
    stream: _titles,
    initialData: const {},
    builder: (context, titles) => StreamBuilder<DownloadsSnapshot>(
      stream: _snapshots,
      builder: (context, snap) {
        final data = snap.data;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Downloads'),
            actions: [if (data != null) _pauseButton(data.paused)],
          ),
          body: data == null
              ? const Center(child: CircularProgressIndicator())
              : _body(context, data, titles.data!),
        );
      },
    ),
  );

  /// [key]'s title: the library's, else a resolved one (asked once).
  String _label(MangaKey key, Map<MangaKey, String> titles) {
    final known = titles[key] ?? _resolved[key];
    if (known != null) return known;
    final resolve = widget.resolveTitle;
    if (resolve != null && _asked.add(key)) {
      unawaited(
        resolve(key).then((t) {
          if (t != null && mounted) setState(() => _resolved[key] = t);
        }),
      );
    }
    return mangaLabel(key, titles);
  }

  Widget _pauseButton(bool paused) => IconButton(
    icon: Icon(paused ? Icons.play_arrow : Icons.pause),
    tooltip: paused ? 'Resume downloads' : 'Pause downloads',
    onPressed: () =>
        unawaited(paused ? widget.service.resume() : widget.service.pause()),
  );

  Widget _body(
    BuildContext context,
    DownloadsSnapshot data,
    Map<MangaKey, String> titles,
  ) {
    final s = widget.service;
    final theme = Theme.of(context);
    const pad = EdgeInsets.fromLTRB(
      AppSpacing.md,
      AppSpacing.lg,
      AppSpacing.md,
      AppSpacing.sm,
    );
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Text(
            'Storage used: ${formatBytes(data.index.totalBytes)}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (data.queue.isEmpty && data.index.mangaKeys.isEmpty)
          const EmptyState(
            icon: Icons.download_outlined,
            title: 'No downloads',
            message: 'Chapters you download appear here.',
          ),
        if (data.queue.isNotEmpty) const SectionHeader('Queue', padding: pad),
        for (final t in data.queue)
          QueueTile(
            task: t,
            mangaTitle: _label(t.mangaKey, titles),
            paused: data.paused,
            onCancel: () => unawaited(s.cancel(t.mangaKey, t.chapter.url)),
            onRetry: () => unawaited(s.retry(t.mangaKey, t.chapter.url)),
          ),
        if (data.index.mangaKeys.isNotEmpty)
          const SectionHeader('Downloaded', padding: pad),
        for (final key in data.index.mangaKeys)
          OfflineMangaTile(
            title: _label(key, titles),
            chapters: data.index.chapters(key),
            onDeleteChapter: (url) => unawaited(s.deleteChapter(key, url)),
            onDeleteAll: () => unawaited(s.deleteManga(key)),
          ),
      ],
    );
  }
}
