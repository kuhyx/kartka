import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// Jump-to-page slider with a "page / total" label.
class PageSlider extends StatelessWidget {
  /// A slider at 0-based [page] of [pageCount].
  const new({
    required this.page,
    required this.pageCount,
    required this.onChanged,
    this.rightToLeft = false,
    super.key,
  });

  /// Current page, 0-based.
  final int page;

  /// Pages in the chapter.
  final int pageCount;

  /// Called with the 0-based page the user picked.
  final ValueChanged<int> onChanged;

  /// Whether the track runs right to left, matching RTL reading.
  final bool rightToLeft;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      '${page + 1} / $pageCount',
      style: Theme.of(context).textTheme.labelLarge,
    );
    if (pageCount < 2) return Center(child: label);
    return Row(
      children: [
        const SizedBox(width: AppSpacing.md),
        label,
        Expanded(
          child: Directionality(
            textDirection: rightToLeft ? TextDirection.rtl : TextDirection.ltr,
            child: Slider(
              value: page.clamp(0, pageCount - 1).toDouble(),
              max: (pageCount - 1).toDouble(),
              divisions: pageCount - 1,
              label: '${page + 1}',
              onChanged: (v) => onChanged(v.round()),
            ),
          ),
        ),
      ],
    );
  }
}
