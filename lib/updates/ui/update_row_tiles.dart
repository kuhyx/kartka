import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kartka/app/routes.dart';
import 'package:kartka/updates/state/update_rows.dart';
import 'package:kartka/updates/state/updates_deps.dart';
import 'package:kartka/updates/ui/update_cover.dart';

/// The widget for one [row]: a day heading, a manga heading that opens the
/// detail page, or a chapter that opens the reader on it.
Widget updateRowTile(BuildContext context, UpdateRow row, CoverBytes? covers) {
  final theme = Theme.of(context);
  switch (row) {
    case DayRow(:final label):
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.xs,
        ),
        child: Text(label, style: theme.textTheme.titleSmall),
      );
    case MangaRow(:final entry):
      return ListTile(
        leading: UpdateCover(url: entry.coverUrl, loader: covers),
        title: Text(entry.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        onTap: () => context.push(mangaRoute(entry.sourceId, entry.mangaUrl)),
      );
    case ChapterRow(:final entry, :final chapter, :final unread):
      return ListTile(
        dense: true,
        contentPadding: const EdgeInsets.only(
          left: AppSpacing.md + updateCoverWidth + AppSpacing.md,
          right: AppSpacing.md,
        ),
        title: Text(
          chapter.name,
          style: unread
              ? null
              : TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
        trailing: unread
            ? _UnreadDot(key: ValueKey('unread ${chapter.url}'))
            : null,
        onTap: () => context.push(
          readRoute(entry.sourceId, entry.mangaUrl, chapter.url),
        ),
      );
  }
}

class _UnreadDot extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Unread',
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        shape: BoxShape.circle,
      ),
      child: const SizedBox.square(dimension: AppSpacing.sm),
    ),
  );
}
