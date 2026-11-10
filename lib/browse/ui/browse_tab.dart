import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kartka/browse/browse_routes.dart';
import 'package:kartka/browse/browse_scope.dart';
import 'package:kartka/browse/language_filter.dart';
import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/browse/state/shared_health_lookup.dart';
import 'package:kartka/browse/ui/language_mark.dart';
import 'package:kartka/browse/ui/language_picker.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/source/manga_source.dart';
import 'package:kartka/core/ui/spoken_label.dart';

/// Spoken section title per origin (never painted).
const Map<SourceOrigin, String> originLabels = {
  SourceOrigin.native: 'Built-in',
  SourceOrigin.suwayomi: 'Suwayomi',
  SourceOrigin.plugin: 'Plugins',
  SourceOrigin.local: 'Local',
};

/// Painted section glyph per origin.
const Map<SourceOrigin, IconData> originIcons = {
  SourceOrigin.native: Icons.inventory_2_outlined,
  SourceOrigin.suwayomi: Icons.dns_outlined,
  SourceOrigin.plugin: Icons.extension_outlined,
  SourceOrigin.local: Icons.folder_outlined,
};

/// The Browse tab: a global search field, then the sources of the selected
/// languages, one section per language in selection order, each grouped by
/// origin and ordered by source-health rank (name order without it).
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
            onPressed: () => unawaited(
              showLanguagePicker(context, deps.languages, [
                for (final s in deps.sources.current) s.ref,
              ]),
            ),
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
              builder: (context, ranks) => ValueListenableBuilder(
                valueListenable: deps.languages,
                builder: (context, selected, _) => _SourceList(
                  sections: sectionSources(
                    [for (final s in sources.data!) s.ref],
                    ranks.data ?? const {},
                    selected,
                  ),
                  anyInstalled: sources.data!.isNotEmpty,
                  ranks: ranks.data ?? const {},
                  health: health,
                ),
              ),
            ),
      ),
    );
  }
}

class _SourceList extends StatelessWidget {
  const new({
    required this.sections,
    required this.anyInstalled,
    required this.ranks,
    required this.health,
  });

  final List<LanguageSection> sections;
  final bool anyInstalled;
  final Map<String, SourceHealthSummary> ranks;
  final SourceHealthLookup? health;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(
                Icons.search,
                semanticLabel: 'Search all sources',
              ),
            ),
            textInputAction: TextInputAction.search,
            onSubmitted: (q) {
              if (q.trim().isNotEmpty) {
                unawaited(context.push(globalSearchRoute(q)));
              }
            },
          ),
        ),
        if (sections.isEmpty && !anyInstalled)
          const EmptyMark(
            icon: Icons.extension_off_outlined,
            semanticLabel: 'No sources',
          )
        else if (sections.isEmpty)
          const EmptyMark(
            icon: Icons.filter_list_off,
            semanticLabel: 'No sources in your languages',
          ),
        for (final section in sections) ...[
          Padding(
            padding: SectionHeader.defaultPadding,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: LanguageMark(
                section.language,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ),
          for (final g in section.groups) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.xs,
              ),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Icon(
                  originIcons[g.origin],
                  color: theme.colorScheme.onSurfaceVariant,
                  semanticLabel: originLabels[g.origin],
                ),
              ),
            ),
            for (final s in g.sources) _SourceTile(s, ranks[s.id], health),
          ],
        ],
      ],
    );
  }
}

class _SourceTile extends StatelessWidget {
  const new(this.source, this.summary, this.health);

  final SourceRef source;
  final SourceHealthSummary? summary;
  final SourceHealthLookup? health;

  @override
  Widget build(BuildContext context) {
    final rank = summary?.rank;
    return ListTile(
      key: ValueKey('source-${source.id}'),
      title: Text(source.name),
      subtitle: Text(
        [source.lang.toUpperCase(), if (rank != null) '#$rank'].join(' · '),
      ),
      trailing: health?.buildBadge(context, source.id, summary),
      onTap: () => unawaited(context.push(sourceRoute(source.id))),
    );
  }
}
