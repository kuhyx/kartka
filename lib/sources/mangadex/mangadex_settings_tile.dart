import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/sources/mangadex/mangadex_settings.dart';
import 'package:kartka/sources/mangadex/mangadex_settings_store.dart';

/// One-line summary, e.g. `en, pl · Safe, Suggestive · data saver`.
String settingsSummary(MangadexSettings s) => [
  s.languages.join(', '),
  [
    for (final r in ContentRating.values)
      if (s.ratings.contains(r)) r.label,
  ].join(', '),
  if (s.dataSaver) 'data saver',
].join(' · ');

/// Languages typed as "en, pt-br" -> `['en', 'pt-br']`.
List<String> parseLanguages(String text) => {
  for (final part in text.split(RegExp(r'[,\s]+')))
    if (part.trim().isNotEmpty) part.trim().toLowerCase(),
}.toList();

/// More-tab tile that shows and edits the MangaDex settings.
class MangadexSettingsTile extends StatelessWidget {
  /// Creates the tile over [store].
  const new({required this.store, super.key});

  /// Settings being shown and edited.
  final MangadexSettingsStore store;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: store,
    builder: (context, s, _) => ListTile(
      leading: const Icon(Icons.menu_book_outlined),
      title: const Text('MangaDex'),
      subtitle: Text(settingsSummary(s)),
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => MangadexSettingsDialog(store: store),
      ),
    ),
  );
}

/// Editor for languages, data saver and the content-rating filter.
class MangadexSettingsDialog extends StatefulWidget {
  /// Creates the dialog over [store].
  const new({required this.store, super.key});

  /// Settings being edited.
  final MangadexSettingsStore store;

  @override
  State<MangadexSettingsDialog> createState() => _DialogState();
}

class _DialogState extends State<MangadexSettingsDialog> {
  late MangadexSettings _draft = widget.store.value;
  late final _langs = TextEditingController(text: _draft.languages.join(', '));

  @override
  void dispose() {
    _langs.dispose();
    super.dispose();
  }

  void _toggle(ContentRating r, {required bool on}) {
    final next = {..._draft.ratings};
    on ? next.add(r) : next.remove(r);
    if (next.isEmpty) return; // At least one rating must stay selected.
    setState(() => _draft = _draft.copyWith(ratings: next));
  }

  Future<void> _save() async {
    final langs = parseLanguages(_langs.text);
    final s = langs.isEmpty ? _draft : _draft.copyWith(languages: langs);
    final nav = Navigator.of(context);
    await widget.store.save(s);
    nav.pop();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('MangaDex'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const Key('mangadex-languages'),
          controller: _langs,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Chapter languages',
            helperText: 'Comma separated, e.g. en, pl, pt-br',
          ),
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: AppSpacing.md),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Data saver'),
          subtitle: const Text('Smaller, compressed page images'),
          value: _draft.dataSaver,
          onChanged: (v) =>
              setState(() => _draft = _draft.copyWith(dataSaver: v)),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text('Content rating', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final r in ContentRating.values)
              FilterChip(
                label: Text(r.label),
                selected: _draft.ratings.contains(r),
                onSelected: (on) => _toggle(r, on: on),
              ),
          ],
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Save')),
    ],
  );
}
