import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kartka/app/feature.dart';
import 'package:kartka/browse/source_registry.dart';
import 'package:kartka/core/source/manga_source.dart';
import 'package:kartka/migration/better/better_controller.dart';
import 'package:kartka/migration/better/better_route.dart';
import 'package:kartka/migration/better/better_screen.dart';
import 'package:kartka/migration/first_value.dart';
import 'package:kartka/migration/migration_deps.dart';
import 'package:kartka/source_health/feed/source_health_feed.dart';
import 'package:kartka/source_health/install/keep_reconciler.dart';
import 'package:kartka/source_health/model/source_health_record.dart';

/// The [betterSourcesRoute] screen over [registry], migrating with [deps].
/// The source-health part supplies the scored feed and the auto-install's
/// flags as services; without them nothing counts as cut or failing.
GoRoute betterSourcesGoRoute(
  KartkaRegistry Function() registry,
  MigrationDeps Function() deps,
) => GoRoute(
  path: betterSourcesRoute,
  builder: (_, _) {
    final r = registry();
    return BetterSourcesScreen(
      controller: BetterSourcesController(
        deps(),
        BetterSourcesInputs(
          records: () => healthRecords(r.maybe<SourceHealthFeed>()),
          sources: () => settledSources(r),
          flagOf: (id) => r.maybe<KeepReconciler>()?.flagOf(id),
        ),
      ),
    );
  },
);

/// The More tile opening [betterSourcesRoute].
Widget betterSourcesTile(BuildContext context) => ListTile(
  leading: const Icon(Icons.auto_fix_high),
  title: const Text('Migrate to better sources'),
  subtitle: const Text('Move entries off cut, blocked or missing sources'),
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

/// Every installed source once the providers re-listed: a provider's first
/// list can be empty while its server answers (contracts §15).
Future<List<MangaSource>> settledSources(KartkaRegistry registry) async {
  final sources = SourceRegistry.fromRegistry(registry);
  try {
    await sources.refresh();
    // Re-listed sources reach the registry a turn of the event loop later.
    await Future<void>.delayed(Duration.zero);
    return sources.current;
  } finally {
    unawaited(sources.dispose());
  }
}
