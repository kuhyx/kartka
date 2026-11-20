import 'dart:async';

import 'package:kartka/app/feature.dart';
import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/browse/source_registry.dart';
import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:kartka/library/ports.dart';
import 'package:kartka/migration/dedupe/library_deduper.dart';
import 'package:kartka/migration/first_value.dart';
import 'package:kartka/migration/migration_deps.dart';

/// The app's [LibraryDeduper]: browse's stored facts, the evaluator's
/// ranks, the installed sources, the shared update run, device-local gate.
LibraryDeduper libraryDeduper(KartkaEnv env, MigrationDeps Function() deps) =>
    LibraryDeduper(
      deps: deps,
      facts: () => env.registry.maybe<DupeFactsLookup>(),
      health: () => healthRanks(env.registry.maybe<SourceHealthLookup>()),
      installed: () => installedSourceIds(env.registry),
      local: env.platform.kv,
      updater: () => env.registry.maybe<LibraryUpdater>(),
      log: DiagnosticsLog.of(env.platform.diagnostics),
    );

/// The first ranking [lookup] emits; null without one, on a read error or
/// after [timeout].
Future<Map<String, SourceHealthSummary>?> healthRanks(
  SourceHealthLookup? lookup, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  if (lookup == null) return null;
  try {
    return await firstValue(lookup.watch()).timeout(timeout);
  } on Object {
    return null;
  }
}

/// Ids of every installed source once the providers re-listed (a first
/// list can be empty while a server answers, contracts §15); a re-list
/// still going after [timeout] is not waited for.
Future<Set<String>> installedSourceIds(
  KartkaRegistry registry, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final sources = SourceRegistry.fromRegistry(registry);
  try {
    await sources.refresh().timeout(timeout, onTimeout: () => const []);
    // Re-listed sources reach the registry a turn of the event loop later.
    await Future<void>.delayed(Duration.zero);
    return {for (final s in sources.current) s.ref.id};
  } finally {
    unawaited(sources.dispose());
  }
}
