import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/downloads/queue/download_index.dart';
import 'package:kartka/downloads/ui/format.dart';

/// One manga's offline chapters: size, per-chapter delete, delete all.
class OfflineMangaTile extends StatelessWidget {
  /// Creates the tile.
  const new({
    required this.title,
    required this.chapters,
    required this.onDeleteChapter,
    required this.onDeleteAll,
    super.key,
  });

  /// Manga display title.
  final String title;

  /// Its offline chapters.
  final List<OfflineChapter> chapters;

  /// Deletes one chapter by url.
  final void Function(String chapterUrl) onDeleteChapter;

  /// Deletes every chapter of the manga.
  final VoidCallback onDeleteAll;

  @override
  Widget build(BuildContext context) {
    final bytes = chapters.fold(0, (sum, c) => sum + c.bytes);
    final count = chapters.length == 1
        ? '1 chapter'
        : '${chapters.length} '
              'chapters';
    return ExpansionTile(
      title: Text(title),
      subtitle: Text('$count · ${formatBytes(bytes)}'),
      children: [
        for (final c in chapters)
          ListTile(
            title: Text(c.chapterName),
            subtitle: Text('${c.pageCount} pages · ${formatBytes(c.bytes)}'),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete chapter',
              onPressed: () => _confirm(
                context,
                'Delete ${c.chapterName}?',
                () => onDeleteChapter(c.chapterUrl),
              ),
            ),
          ),
        ListTile(
          leading: const Icon(Icons.delete_sweep_outlined),
          title: const Text('Delete all chapters'),
          onTap: () => _confirm(context, 'Delete all of $title?', onDeleteAll),
        ),
      ],
    );
  }

  Future<void> _confirm(
    BuildContext context,
    String title,
    VoidCallback action,
  ) async {
    final ok = await confirmDestructive(
      context,
      title: title,
      message: 'The pages are removed from this device.',
    );
    if (ok) action();
  }
}
