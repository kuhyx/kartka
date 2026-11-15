import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/updates/state/updates_deps.dart';
import 'package:kartka/updates/ui/update_cover.dart';
import 'package:kartka/updates/ui/update_groups.dart';

/// Height under the cover for the one-line title.
const double updateTileLabelHeight = AppSpacing.lg;

/// One manga in the Updates grid: square cover, unread count, one-line
/// title. Fills the cell it is given; [onTap] opens its sheet.
class UpdateTile extends StatelessWidget {
  /// Creates the tile of [group].
  const new({
    required this.group,
    required this.covers,
    required this.onTap,
    super.key,
  });

  /// The manga and its new chapters.
  final UpdateGroup group;

  /// Cover loader.
  final CoverBytes? covers;

  /// Opens the chapter sheet.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final entry = group.entry;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: LayoutBuilder(
        builder: (context, box) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox.square(
              dimension: box.maxWidth,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  UpdateCover(
                    url: entry.coverUrl,
                    loader: covers,
                    size: Size.square(box.maxWidth),
                  ),
                  if (group.unread > 0)
                    Positioned(
                      top: AppSpacing.xs,
                      left: AppSpacing.xs,
                      child: _Badge(group.unread),
                    ),
                ],
              ),
            ),
            SizedBox(
              height: updateTileLabelHeight,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const new(this.count);

  final int count;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$count unread',
    child: ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppPalette.accent,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          child: Text(
            '$count',
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: AppPalette.onFill),
          ),
        ),
      ),
    ),
  );
}
