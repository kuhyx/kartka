import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kartka/browse/language_filter.dart';
import 'package:kartka/browse/state/browse_language_store.dart';
import 'package:kartka/browse/ui/language_mark.dart';
import 'package:kartka/core/models/source_ref.dart';
import 'package:kartka/core/ui/spoken_label.dart';

/// Opens the Browse language checklist over [sources].
Future<void> showLanguagePicker(
  BuildContext context,
  BrowseLanguageStore store,
  Iterable<SourceRef> sources,
) => showDialog<void>(
  context: context,
  builder: (_) =>
      LanguagePickerDialog(store: store, counts: languageCounts(sources)),
);

/// A checklist of the languages installed sources have, with counts; the
/// selected ones first. Every tap is persisted at once.
class LanguagePickerDialog extends StatelessWidget {
  /// Creates the dialog.
  const new({required this.store, required this.counts, super.key});

  /// Selection store.
  final BrowseLanguageStore store;

  /// Installed sources per language bucket.
  final Map<String, int> counts;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<List<String>>(
    valueListenable: store,
    builder: (context, selected, _) {
      final langs = pickerLanguages(counts, selected);
      return AlertDialog(
        title: const Icon(
          Icons.language_outlined,
          size: 32,
          semanticLabel: 'Languages',
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: langs.isEmpty
              ? const EmptyMark(
                  icon: Icons.extension_off_outlined,
                  semanticLabel: 'No sources installed yet',
                )
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final l in langs)
                      CheckboxListTile(
                        key: ValueKey('lang-$l'),
                        value: selected.contains(l),
                        title: LanguageMark(l),
                        subtitle: Text(
                          '${counts[l]}',
                          semanticsLabel: _count(counts[l]!),
                        ),
                        onChanged: (_) => unawaited(store.toggle(l)),
                      ),
                  ],
                ),
        ),
        actions: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.check, semanticLabel: 'Done'),
          ),
        ],
      );
    },
  );
}

String _count(int n) => n == 1 ? '1 source' : '$n sources';
