import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/core/source/manga_source.dart';
import 'package:kartka/migration/better/better_controller.dart';
import 'package:kartka/source_health/model/source_health_record.dart';

import '../fakes.dart';

/// A world for "Migrate to better sources": a library on a cut source
/// (`old`), two installed keep sources (`best` rank 1, `good` rank 2) and
/// one healthy keep source the library also reads (`fine`).
class BetterWorld {
  /// The usual migration world.
  final world = World();

  /// The cut source the library entries sit on.
  final old = ScriptedSource('old', name: 'Old Site');

  /// The highest-ranked keep source.
  final best = ScriptedSource('best', name: 'Best Site');

  /// The second keep source.
  final good = ScriptedSource('good', name: 'Good Site');

  /// A keep source already used by the library.
  final fine = ScriptedSource('fine', name: 'Fine Site');

  /// Published records (scored feed order does not matter).
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
      id: 'fine',
      name: 'Fine Site',
      rank: 3,
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
  late List<MangaSource> installed = [old, best, good, fine];

  /// Auto-install flags by source id.
  final flags = <String, String>{};

  /// A controller over this world.
  BetterSourcesController controller() => BetterSourcesController(
    world.deps,
    BetterSourcesInputs(
      records: () async => records,
      sources: () async => installed,
      flagOf: (id) => flags[id],
    ),
  );
}
