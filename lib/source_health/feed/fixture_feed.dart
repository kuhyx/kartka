import 'package:kartka/source_health/feed/source_health_feed.dart';
import 'package:kartka/source_health/model/source_health_record.dart';

/// A [SourceHealthFeed] over a fixed, already-decoded evaluator result
/// (e.g. `tools/source_eval/out/latest.json`): tests, demos and offline runs.
class FixtureSourceHealthFeed implements SourceHealthFeed {
  /// Creates a feed over decoded [json] in any [parseHealthCollection] shape.
  new(Object? json) : _records = parseHealthCollection(json);

  final List<SourceHealthRecord> _records;

  @override
  Stream<List<SourceHealthRecord>> watch() => Stream.value(_records);
}
