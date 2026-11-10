import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/core/ui/confirm_mark.dart';
import 'package:kartka/core/ui/spoken_label.dart';
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
    final n = chapters.length;
    final count = n == 1 ? '1 chapter' : '$n chapters';
    return ExpansionTile(
      title: Text(title),
      subtitle: _Figures(
        spoken: '$count · ${formatBytes(bytes)}',
        icon: Icons.menu_book_outlined,
        count: n,
        bytes: bytes,
      ),
      children: [
        for (final c in chapters)
          ListTile(
            title: Text(c.chapterName),
            subtitle: _Figures(
              spoken: '${c.pageCount} pages · ${formatBytes(c.bytes)}',
              icon: Icons.photo_library_outlined,
              count: c.pageCount,
              bytes: c.bytes,
            ),
            trailing: IconButton(
              icon: const Icon(
                Icons.delete_outline,
                semanticLabel: 'Delete chapter',
              ),
              onPressed: () => _confirm(
                context,
                Icons.delete_outline,
                'Delete ${c.chapterName}?',
                () => onDeleteChapter(c.chapterUrl),
              ),
            ),
          ),
        ListTile(
          leading: const Icon(
            Icons.delete_sweep_outlined,
            semanticLabel: 'Delete all chapters',
          ),
          onTap: () => _confirm(
            context,
            Icons.delete_sweep_outlined,
            'Delete all of $title?',
            onDeleteAll,
          ),
        ),
      ],
    );
  }

  Future<void> _confirm(
    BuildContext context,
    IconData icon,
    String question,
    VoidCallback action,
  ) async {
    final ok = await confirmMark(context, icon: icon, semanticLabel: question);
    if (ok) action();
  }
}

/// "[count] [icon] · size", spoken as [spoken].
class _Figures extends StatelessWidget {
  const new({
    required this.spoken,
    required this.icon,
    required this.count,
    required this.bytes,
  });

  final String spoken;
  final IconData icon;
  final int count;
  final int bytes;

  @override
  Widget build(BuildContext context) => SpokenLabel(
    semanticLabel: spoken,
    child: ExcludeSemantics(
      child: Row(
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: AppSpacing.xs),
          Text('$count'),
          const SizedBox(width: AppSpacing.md),
          const Icon(Icons.storage, size: 16),
          const SizedBox(width: AppSpacing.xs),
          Text(formatBytes(bytes)),
        ],
      ),
    ),
  );
}
