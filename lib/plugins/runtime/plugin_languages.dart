/// The Plugins screen language filter: which languages the Available list
/// offers. Buckets and labels are Browse's, so `multi` reads as `all`.
library;

import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/browse/language_filter.dart';
import 'package:kartka/plugins/runtime/plugin_manager.dart';

/// The selection until the user picks: multi-language and English plugins.
const List<String> kDefaultPluginLanguages = [kAllLanguages, 'en'];

/// The offers of [all] in a [selected] language bucket, plus every installed
/// one whatever its language, so an Update is never hidden.
List<AvailablePlugin> shownPlugins(
  List<AvailablePlugin> all,
  List<String> selected,
) => [
  for (final p in all)
    if (p.availability != PluginAvailability.available ||
        selected.contains(languageBucket(p.entry.manifest.lang)))
      p,
];

/// Number of [plugins] per language bucket.
Map<String, int> pluginLanguageCounts(Iterable<AvailablePlugin> plugins) {
  final counts = <String, int>{};
  for (final p in plugins) {
    final bucket = languageBucket(p.entry.manifest.lang);
    counts.update(bucket, (n) => n + 1, ifAbsent: () => 1);
  }
  return counts;
}

String _plugins(int n) => n == 1 ? '1 plugin' : '$n plugins';

/// Language-filter chip (the picked names); opens a checklist that reports
/// every change.
class PluginLanguagesChip extends StatelessWidget {
  /// Creates the chip.
  const new({
    required this.selected,
    required this.counts,
    required this.onChanged,
    super.key,
  });

  /// Selected buckets, in the order picked.
  final List<String> selected;

  /// Offers per bucket.
  final Map<String, int> counts;

  /// Receives the new selection on every tap.
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final names = selected.map(languageLabel).join(', ');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ActionChip(
          key: const Key('plugin-languages'),
          avatar: const Icon(Icons.translate, semanticLabel: 'Languages'),
          label: names.isEmpty
              ? const Icon(Icons.block, size: 18, semanticLabel: 'none')
              : Text(names),
          onPressed: () => unawaited(
            showDialog<void>(
              context: context,
              builder: (_) => _LanguagesDialog(selected, counts, onChanged),
            ),
          ),
        ),
      ),
    );
  }
}

class _LanguagesDialog extends StatefulWidget {
  const new(this.initial, this.counts, this.onChanged);

  final List<String> initial;
  final Map<String, int> counts;
  final ValueChanged<List<String>> onChanged;

  @override
  State<_LanguagesDialog> createState() => _LanguagesDialogState();
}

class _LanguagesDialogState extends State<_LanguagesDialog> {
  late List<String> _selected = widget.initial;

  void _toggle(String lang) {
    final next = [..._selected];
    if (!next.remove(lang)) next.add(lang);
    setState(() => _selected = next);
    widget.onChanged(_selected);
  }

  @override
  Widget build(BuildContext context) {
    // The selected ones first (even with no offers, so they can be
    // unticked), then the other languages on offer by code.
    final rest = widget.counts.keys.where((l) => !_selected.contains(l));
    final langs = [..._selected, ...rest.toList()..sort()];
    return AlertDialog(
      title: const Icon(Icons.translate, size: 32, semanticLabel: 'Languages'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final l in langs)
              CheckboxListTile(
                value: _selected.contains(l),
                title: Text(languageLabel(l)),
                subtitle: Text('${widget.counts[l] ?? 0}'),
                onChanged: (_) => _toggle(l),
              ),
          ],
        ),
      ),
      actions: [
        IconButton(
          style: IconButton.styleFrom(minimumSize: const Size.square(48)),
          icon: const Icon(Icons.check, semanticLabel: 'Done'),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// Spoken label for an Available list whose [hidden] offers are all
/// filtered out.
String hiddenByLanguageMessage(int hidden) =>
    '${_plugins(hidden)} ${hidden == 1 ? 'is' : 'are'} in other languages. '
    'Pick more in Languages.';
