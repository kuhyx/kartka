import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:kartka/app/feature.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/source/manga_source.dart';
import 'package:kartka/core/source/source_provider.dart';
import 'package:kartka/migration/better/better_route.dart';
import 'package:kartka/migration/first_value.dart';
import 'package:kartka/migration/migration_deps.dart';
import 'package:kartka/migration/walk/walk_controller.dart';
import 'package:kartka/migration/walk/walk_screen.dart';
import 'package:kartka/platform/cover_cache.dart';
import 'package:kartka/source_health/feed/source_health_feed.dart';
import 'package:kartka/source_health/install/keep_reconciler.dart';
import 'package:kartka/source_health/model/source_health_meta.dart';
import 'package:kartka/source_health/model/source_health_record.dart';
import 'package:material_ui/material_ui.dart';

/// The one-by-one migration over [registry], migrating with [deps]: the
/// [scope] of the library, or only [onlyKeys]. The source-health part
/// supplies the scored feed and the auto-install's flags as services;
/// without them no source is a keep target, and nothing counts as cut.
MigrationWalkScreen migrationWalk(
  KartkaRegistry registry,
  MigrationDeps deps, {
  WalkScope scope = WalkScope.library,
  Set<MangaKey>? onlyKeys,
}) => MigrationWalkScreen(
  controller: MigrationWalkController(
    deps,
    MigrationInputs(
      records: () => healthRecords(registry.maybe<SourceHealthFeed>()),
      sources: () => installedSources(registry),
      meta: () => healthMeta(registry.maybe<SourceHealthFeed>()),
      flagOf: (id) => registry.maybe<KeepReconciler>()?.flagOf(id),
    ),
    scope: scope,
    onlyKeys: onlyKeys,
  ),
  coverLoader: registry.maybe<CoverCache>()?.get,
);

/// The [betterSourcesRoute] walk: the entries whose source should be left.
GoRoute betterSourcesGoRoute(
  KartkaRegistry Function() registry,
  MigrationDeps Function() deps,
) => GoRoute(
  path: betterSourcesRoute,
  builder: (_, _) => migrationWalk(registry(), deps(), scope: WalkScope.better),
);

/// The More tile opening [betterSourcesRoute].
Widget betterSourcesTile(BuildContext context) => ListTile(
  leading: const Icon(
    Icons.auto_fix_high,
    semanticLabel:
        'Migrate to better sources. Move entries off cut, blocked or '
        'missing sources',
  ),
  onTap: () => unawaited(context.push(betterSourcesRoute)),
);

/// The first ranking of [feed]; empty without one, on a read error or
/// after [timeout] (the screen still lists entries on missing sources).
Future<List<SourceHealthRecord>> healthRecords(
  SourceHealthFeed? feed, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  if (feed == null) return const [];
  try {
    return await firstValue(feed.watch()).timeout(timeout);
  } on Object {
    return const [];
  }
}

/// Every installed source: the current list of each provider (the
/// Suwayomi one keeps its last fetch, so this is instant once the app has
/// listed it), first id wins. No re-list: it queued behind every other
/// request to the server. A provider that does not answer within [timeout]
/// counts as empty.
Future<List<MangaSource>> installedSources(
  KartkaRegistry registry, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final lists = await Future.wait([
    for (final p in registry.all<SourceProvider>())
      firstValue(p.watch()).timeout(timeout).onError<Object>((_, _) => []),
  ]);
  final byId = <String, MangaSource>{};
  for (final s in lists.expand((l) => l)) {
    byId.putIfAbsent(s.ref.id, () => s);
  }
  return byId.values.toList();
}

/// The published run's meta (its `rejectedIds`); null without a feed, on
/// a read error or after [timeout].
Future<SourceHealthMeta?> healthMeta(
  SourceHealthFeed? feed, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  if (feed == null) return null;
  try {
    return await firstValue(feed.watchMeta()).timeout(timeout);
  } on Object {
    return null;
  }
}
