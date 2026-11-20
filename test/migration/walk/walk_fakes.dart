import 'dart:async';

import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/source/manga_source.dart';
import 'package:kartka/migration/walk/walk_controller.dart';
import 'package:kartka/platform/blob_store.dart';
import 'package:kartka/source_health/model/source_health_meta.dart';
import 'package:kartka/source_health/model/source_health_record.dart';

import '../fakes.dart';

/// A world for the walk: a library on a cut source (`old`) and two
/// installed keep sources (`best` rank 1, `good` rank 2), plus the usual
/// Atsumaru.
class WalkWorld {
  /// The world, its backups going to [backups].
  new({BlobStore? backups}) : world = World(backups: backups);

  /// The usual migration world.
  final World world;

  /// The cut source the library entries sit on.
  final old = ScriptedSource('old', name: 'Old Site');

  /// The highest-ranked keep source.
  final best = ScriptedSource('best', name: 'Best Site');

  /// The second keep source.
  final good = ScriptedSource('good', name: 'Good Site');

  /// Published records.
  List<SourceHealthRecord> records = const [
    SourceHealthRecord(
      id: 'good',
      name: 'Good Site',
      rank: 2,
      verdict: HealthVerdict.keep,
    ),
    SourceHealthRecord(
      id: 'best',
      name: 'Best Site',
      rank: 1,
      verdict: HealthVerdict.keep,
    ),
    SourceHealthRecord(
      id: 'old',
      name: 'Old Site',
      rank: 9,
      verdict: HealthVerdict.cut,
    ),
  ];

  /// Installed sources.
  late List<MangaSource> installed = [old, best, good];

  /// Auto-install flags by source id.
  final flags = <String, String>{};

  /// Sources rejected for good (the run meta's `rejectedIds`).
  Set<String> rejected = const {};

  /// When set, the installed-source list waits for it.
  Completer<void>? sourcesGate;

  /// Adds [titles] on `old`, each offered by `best` under the same title.
  Future<void> library(List<String> titles) async {
    for (final t in titles) {
      await world.add(t);
      best.offer(t, t, '/best/$t');
    }
  }

  /// A controller over this world.
  MigrationWalkController controller({
    WalkScope scope = WalkScope.library,
    Set<MangaKey>? onlyKeys,
  }) => MigrationWalkController(
    world.deps,
    MigrationInputs(
      records: () async => records,
      sources: () async {
        await sourcesGate?.future;
        return installed;
      },
      meta: () async => SourceHealthMeta(rejectedIds: rejected),
      flagOf: (id) => flags[id],
    ),
    scope: scope,
    onlyKeys: onlyKeys,
  );
}
