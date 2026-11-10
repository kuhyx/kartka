import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/sources/mangadex/mangadex_mapper.dart';
import 'package:kartka/sources/mangadex/mangadex_settings.dart';
import 'package:kartka/sources/mangadex/mangadex_settings_store.dart';

/// One-line summary, e.g. `en, pl · Safe, Suggestive`: language codes and
/// MangaDex's own rating names. Data saver shows as an icon instead.
String settingsSummary(MangadexSettings s) => [
  s.languages.join(', '),
  [
    for (final r in ContentRating.values)
      if (s.ratings.contains(r)) r.label,
  ].join(', '),
].join(' · ');

const _dataSaver = 'Data saver: smaller, compressed page images';
const _tap = Size.square(48);

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
      title: const Text(mangadexSourceName),
      subtitle: Text(settingsSummary(s)),
      trailing: s.dataSaver
          ? const Icon(Icons.data_saver_on, semanticLabel: _dataSaver)
          : null,
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
    title: const Text(mangadexSourceName),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const Key('mangadex-languages'),
          controller: _langs,
          autofocus: true,
          decoration: const InputDecoration(
            prefixIcon: Icon(
              Icons.translate,
              semanticLabel: 'Chapter languages, comma separated',
            ),
          ),
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: AppSpacing.md),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Align(
            alignment: Alignment.centerLeft,
            child: Icon(Icons.data_saver_on, semanticLabel: _dataSaver),
          ),
          value: _draft.dataSaver,
          onChanged: (v) =>
              setState(() => _draft = _draft.copyWith(dataSaver: v)),
        ),
        const SizedBox(height: AppSpacing.sm),
        const Icon(Icons.shield_outlined, semanticLabel: 'Content rating'),
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
      IconButton(
        style: IconButton.styleFrom(minimumSize: _tap),
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(Icons.close, semanticLabel: 'Cancel'),
      ),
      IconButton.filled(
        style: IconButton.styleFrom(minimumSize: _tap),
        onPressed: _save,
        icon: const Icon(Icons.check, semanticLabel: 'Save'),
      ),
    ],
  );
}
