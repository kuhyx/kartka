import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kartka/app/fit_pages.dart';
import 'package:kartka/browse/browse_routes.dart';
import 'package:kartka/browse/browse_scope.dart';
import 'package:kartka/browse/language_filter.dart';
import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/browse/source_ordering.dart';
import 'package:kartka/browse/state/shared_health_lookup.dart';
import 'package:kartka/browse/ui/browse_filters.dart';
import 'package:kartka/browse/ui/language_picker.dart';
import 'package:kartka/browse/ui/source_tile.dart';
import 'package:kartka/core/source/manga_source.dart';
import 'package:kartka/core/ui/spoken_label.dart';

/// The Browse tab: a global search field, one chip row (All, then each
/// selected language that has sources; the choice is remembered) and a
/// paged grid of the chosen sources, ordered by source-health rank (name
/// order without it). It always fits one screen; overflow moves to
/// further pages.
class BrowseTab extends StatefulWidget {
  /// Creates the tab.
  const new({super.key});

  @override
  State<BrowseTab> createState() => _BrowseTabState();
}

class _BrowseTabState extends State<BrowseTab> {
  // Subscribed once per mount: a stream built in build() resubscribed on
  // every sources emission, re-reading the source_health tree each time.
  late final BrowseDeps _deps = BrowseScope.of(context);
  late final Stream<List<MangaSource>> _sources = _deps.sources.watch();
  late final Stream<Map<String, SourceHealthSummary>>? _ranks = _deps.health
      ?.watch();

  void _pickLanguages() => unawaited(
    showLanguagePicker(context, _deps.languages, [
      for (final s in _deps.sources.current) s.ref,
    ]),
  );

  @override
  Widget build(BuildContext context) {
    final deps = _deps;
    final health = deps.health;
    return Scaffold(
      appBar: AppBar(
        title: const Icon(Icons.menu_book_outlined, semanticLabel: 'Browse'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list, semanticLabel: 'Languages'),
            onPressed: _pickLanguages,
          ),
        ],
      ),
      body: StreamBuilder<List<MangaSource>>(
        stream: _sources,
        initialData: deps.sources.current,
        builder: (context, sources) =>
            StreamBuilder<Map<String, SourceHealthSummary>>(
              stream: _ranks,
              initialData: switch (health) {
                SharedHealthLookup(:final latest?) => latest,
                _ => const {},
              },
              builder: (context, ranks) => ListenableBuilder(
                listenable: Listenable.merge([deps.languages, deps.shown]),
                builder: (context, _) => _body(
                  sectionSources(
                    [for (final s in sources.data!) s.ref],
                    ranks.data ?? const {},
                    deps.languages.value,
                  ),
                  sources.data!.isNotEmpty,
                  ranks.data ?? const {},
                  health,
                ),
              ),
            ),
      ),
    );
  }

  Widget _body(
    List<LanguageSection> sections,
    bool anyInstalled,
    Map<String, SourceHealthSummary> ranks,
    SourceHealthLookup? health,
  ) {
    final shown = _deps.shown.value;
    // A remembered language that lost its sources falls back to All.
    final section = sections.where((s) => s.language == shown).firstOrNull;
    final list = orderSources([
      for (final sec in section == null ? sections : [section])
        for (final g in sec.groups) ...g.sources,
    ], ranks);
    return Column(
      children: [
        const _SearchField(),
        LanguageChips(
          languages: [for (final s in sections) s.language],
          current: section?.language,
          onSelect: (l) => unawaited(_deps.shown.set(l)),
          onMore: _pickLanguages,
        ),
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: list.isNotEmpty
              ? FitPages(
                  // A new chip starts on its first page.
                  key: ValueKey(section?.language),
                  itemCount: list.length,
                  minSquare: 0.7,
                  itemBuilder: (_, i) =>
                      SourceTile(list[i], ranks[list[i].id], health),
                )
              : anyInstalled
              ? const EmptyMark(
                  icon: Icons.filter_list_off,
                  semanticLabel: 'No sources in your languages',
                )
              : const EmptyMark(
                  icon: Icons.extension_off_outlined,
                  semanticLabel: 'No sources',
                ),
        ),
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.md,
      AppSpacing.sm,
      AppSpacing.md,
      AppSpacing.sm,
    ),
    child: TextField(
      decoration: const InputDecoration(
        prefixIcon: Icon(Icons.search, semanticLabel: 'Search all sources'),
      ),
      textInputAction: TextInputAction.search,
      onSubmitted: (q) {
        if (q.trim().isNotEmpty) {
          unawaited(context.push(globalSearchRoute(q)));
        }
      },
    ),
  );
}
