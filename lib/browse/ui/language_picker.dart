import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kartka/browse/language_filter.dart';
import 'package:kartka/browse/state/browse_language_store.dart';
import 'package:kartka/core/models/source_ref.dart';

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
        title: const Text('Languages'),
        content: SizedBox(
          width: double.maxFinite,
          child: langs.isEmpty
              ? const Text('No sources installed yet.')
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final l in langs)
                      CheckboxListTile(
                        key: ValueKey('lang-$l'),
                        value: selected.contains(l),
                        title: Text(languageLabel(l)),
                        subtitle: Text(_count(counts[l]!)),
                        onChanged: (_) => unawaited(store.toggle(l)),
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      );
    },
  );
}

String _count(int n) => n == 1 ? '1 source' : '$n sources';
