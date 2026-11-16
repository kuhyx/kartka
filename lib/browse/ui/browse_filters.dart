import 'package:design_system/design_system.dart';
import 'package:kartka/browse/ui/language_mark.dart';
import 'package:kartka/core/models/models.dart';
import 'package:material_ui/material_ui.dart';

/// Spoken origin name per origin (never painted).
const Map<SourceOrigin, String> originLabels = {
  SourceOrigin.native: 'Built-in',
  SourceOrigin.suwayomi: 'Suwayomi',
  SourceOrigin.plugin: 'Plugins',
  SourceOrigin.local: 'Local',
};

/// Painted origin glyph per origin.
const Map<SourceOrigin, IconData> originIcons = {
  SourceOrigin.native: Icons.inventory_2_outlined,
  SourceOrigin.suwayomi: Icons.dns_outlined,
  SourceOrigin.plugin: Icons.extension_outlined,
  SourceOrigin.local: Icons.folder_outlined,
};

/// The one chip row of the Browse tab, scrolling sideways, never down:
/// "All" (every selected language) first, then each language that has
/// sources, [current] marked (null = All), then a "+" chip that calls
/// [onMore] (the language picker).
class LanguageChips extends StatelessWidget {
  /// Creates the row.
  const new({
    required this.languages,
    required this.current,
    required this.onSelect,
    required this.onMore,
    super.key,
  });

  /// Language buckets, in selection order.
  final List<String> languages;

  /// The bucket the grid shows; null for All.
  final String? current;

  /// Called with the tapped bucket (null for All).
  final ValueChanged<String?> onSelect;

  /// Called by the "+" chip.
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final chips = [
      ChoiceChip(
        key: const ValueKey('lang-chip-*'),
        label: const Icon(
          Icons.apps,
          size: AppSpacing.md,
          semanticLabel: 'Every selected language',
        ),
        selected: current == null,
        onSelected: (_) => onSelect(null),
      ),
      for (final l in languages)
        ChoiceChip(
          key: ValueKey('lang-chip-$l'),
          label: LanguageMark(l),
          selected: l == current,
          onSelected: (_) => onSelect(l),
        ),
      ActionChip(
        key: const ValueKey('lang-add'),
        label: const Icon(
          Icons.add,
          size: AppSpacing.md,
          semanticLabel: 'Add language',
        ),
        onPressed: onMore,
      ),
    ];
    return SizedBox(
      height: AppSpacing.xxl - AppSpacing.sm,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        children: [
          for (final c in chips)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: Center(child: c),
            ),
        ],
      ),
    );
  }
}
