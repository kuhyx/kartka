import 'package:kartka/source_health/feed/source_health_feed.dart';
import 'package:kartka/source_health/model/source_health_meta.dart';
import 'package:kartka/source_health/model/source_health_record.dart';

/// A [SourceHealthFeed] over a fixed, already-decoded evaluator result
/// (e.g. `tools/source_eval/out/latest.json`): tests, demos and offline runs.
class FixtureSourceHealthFeed implements SourceHealthFeed {
  /// Creates a feed over decoded [json] in any [parseHealthCollection] shape,
  /// plus an optional decoded `source_health_meta` node.
  new(Object? json, {Object? meta})
    : _records = parseHealthCollection(json),
      _meta = SourceHealthMeta.fromJson(meta);

  final List<SourceHealthRecord> _records;
  final SourceHealthMeta? _meta;

  @override
  Stream<List<SourceHealthRecord>> watch() => Stream.value(_records);

  @override
  Stream<SourceHealthMeta?> watchMeta() => Stream.value(_meta);
}
