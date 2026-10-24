import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kartka/browse/browse_routes.dart';
import 'package:kartka/browse/browse_scope.dart';
import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/browse/source_ordering.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/source/manga_source.dart';

/// Section title per origin.
const originLabels = {
  SourceOrigin.native: 'Built-in',
  SourceOrigin.suwayomi: 'Suwayomi',
  SourceOrigin.plugin: 'Plugins',
  SourceOrigin.local: 'Local',
};

/// The Browse tab: a global search field, then every source grouped by
/// origin and ordered by source-health rank (name order without it).
class BrowseTab extends StatelessWidget {
  /// Creates the tab.
  const BrowseTab({super.key});

  @override
  Widget build(BuildContext context) {
    final deps = BrowseScope.of(context);
    final health = deps.health;
    return StreamBuilder<List<MangaSource>>(
      stream: deps.sources.watch(),
      initialData: deps.sources.current,
      builder: (context, sources) =>
          StreamBuilder<Map<String, SourceHealthSummary>>(
            stream: health?.watch(),
            initialData: const {},
            builder: (context, ranks) => _SourceList(
              groups: groupSources(
                [for (final s in sources.data!) s.ref],
                ranks.data ?? const {},
              ),
              ranks: ranks.data ?? const {},
              health: health,
            ),
          ),
    );
  }
}

class _SourceList extends StatelessWidget {
  const _SourceList({
    required this.groups,
    required this.ranks,
    required this.health,
  });

  final List<SourceGroup> groups;
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
              labelText: 'Search all sources',
              prefixIcon: Icon(Icons.search),
            ),
            textInputAction: TextInputAction.search,
            onSubmitted: (q) {
              if (q.trim().isNotEmpty) context.push(globalSearchRoute(q));
            },
          ),
        ),
        if (groups.isEmpty)
          const EmptyState(
            icon: Icons.extension_off_outlined,
            title: 'No sources',
            message: 'Install a plugin or connect Suwayomi to browse.',
          ),
        for (final g in groups) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: Text(
              originLabels[g.origin]!,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          for (final s in g.sources) _SourceTile(s, ranks[s.id], health),
        ],
      ],
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile(this.source, this.summary, this.health);

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
      onTap: () => context.push(sourceRoute(source.id)),
    );
  }
}
