import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/source_health/metric_text.dart';
import 'package:kartka/source_health/model/source_health_record.dart';
import 'package:kartka/source_health/ui/health_badge.dart';
import 'package:kartka/source_health/ui/health_icons.dart';
import 'package:kartka/source_health/ui/source_line_mark.dart';

/// Compact tile of the Sources grid: name; health glyph + rank, score and
/// Tap opens the detail page, long-press the sheet with the full card
/// and the install action.
/// the sheet with the full card and the install action.
class SourceTile extends StatelessWidget {
  /// Creates a tile for [record].
  new({required this.record, required this.onOpen, required this.onMenu})
    : super(key: ValueKey('source-${record.id}'));

  /// The source.
  final SourceHealthRecord record;

  /// Opens the detail page of [record].
  final VoidCallback onOpen;

  /// Opens the long-press sheet of [record].
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final r = record;
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        onLongPress: onMenu,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                spacing: AppSpacing.xs,
                children: [
                  Expanded(
                    child: Text(
                      r.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  if (r.needsBrowserEngine)
                    Icon(
                      Icons.warning_amber_rounded,
                      size: AppTextSize.body,
                      color: statusColors(context).warning,
                      semanticLabel: 'Needs browser engine',
                    ),
                ],
              ),
              // Scales down rather than overflows on long ranks and verdicts.
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  spacing: AppSpacing.sm,
                  children: [
                    HealthBadge(verdict: r.verdict, rank: r.rank),
                    Text(scoreText(r.score), style: theme.textTheme.titleSmall),
                    if (r.cutReasons.isNotEmpty)
                      IconValue(
                        Icons.error_outline,
                        '${r.cutReasons.length}',
                        semanticLabel: 'Failing checks',
                        color: statusColors(context).danger,
                      ),
                  ],
                ),
              ),
              SourceLineMark(r),
            ],
          ),
        ),
      ),
    );
  }
}
