/// Pure planning steps of the Keep auto-install (`KeepReconciler`).
library;

import 'dart:math' as math;

import 'package:kartka/source_health/model/source_health_meta.dart';
import 'package:kartka/source_health/model/source_health_record.dart';
import 'package:kartka/source_health/ranking.dart';

/// The publish a snapshot belongs to: the run id, else (runs before the
/// meta node) the newest probe time; null when there is neither. Records
/// carrying `defaultScore` come from a run that also wrote meta, so a null
/// [meta] there means "not read yet": null, as `ScoredHealthFeed` reads it.
String? publishIdOf(List<SourceHealthRecord> records, SourceHealthMeta? meta) {
  if (meta != null) return meta.runId;
  if (records.any((r) => r.defaultScore != null)) return null;
  return lastEvaluated(records)?.toUtc().toIso8601String();
}

/// The installs [keep] needs, one group of records per install: records
/// with `pkg` whose package is not in [packages] (grouped by package: one
/// `all` extension serves many sources), else records with `plugin` whose
/// plugin is not in [plugins]. A null set is a side that could not be read:
/// nothing is planned there. `pkg` wins over `plugin`, as on the button.
List<List<SourceHealthRecord>> planKeepInstalls(
  List<SourceHealthRecord> keep, {
  required Set<String>? packages,
  required Set<String>? plugins,
}) {
  final jobs = <String, List<SourceHealthRecord>>{};
  for (final r in keep) {
    if (r.pkg case final pkg?) {
      if (packages != null && !packages.contains(pkg)) {
        (jobs['pkg:$pkg'] ??= []).add(r);
      }
    } else if (r.plugin case final ref?) {
      if (plugins != null && !plugins.contains(ref.id)) {
        (jobs['plugin:${ref.id}'] ??= []).add(r);
      }
    }
  }
  return jobs.values.toList();
}

/// What [installer] reports as installed through [read]; null when no
/// installer is registered, it is not an [L], or the read failed (nothing
/// is planned on that side).
Future<Set<String>?> installedOf<L>(
  Object? installer,
  Future<Set<String>> Function(L lister) read,
) async {
  if (installer is! L) return null;
  try {
    return await read(installer);
  } on Object {
    return null;
  }
}

/// Runs [run] over [items] with at most [width] in flight, in order.
Future<void> runPooled<T>(
  List<T> items,
  int width,
  Future<void> Function(T) run,
) async {
  var next = 0;
  Future<void> worker() async {
    while (next < items.length) {
      await run(items[next++]);
    }
  }

  await Future.wait([
    for (var i = 0; i < math.min(width, items.length); i++) worker(),
  ]);
}
