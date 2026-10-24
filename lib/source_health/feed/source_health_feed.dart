/// Where the Sources ranking gets its §5 records from.
library;

import 'package:kartka/source_health/model/json_read.dart';
import 'package:kartka/source_health/model/source_health_record.dart';

/// A live view of every source's latest evaluation.
abstract interface class SourceHealthFeed {
  /// Emits the full ranking now and again on every evaluator update. Read
  /// failures arrive as stream errors; the UI shows them, never hides them.
  Stream<List<SourceHealthRecord>> watch();
}

/// Parses a collection of §5 records in any shape the evaluator emits:
/// a JSON list, the RTDB map keyed by `sourceIdHash`, or `{sources: [...]}`
/// (the evaluator's run file). Malformed entries are skipped; when an id
/// appears twice the newest `probedAt` wins, keeping the first position.
List<SourceHealthRecord> parseHealthCollection(Object? json) {
  final map = asMap(json);
  final sources = map?['sources'];
  final entries = switch (json) {
    _ when sources is List => sources,
    final List<Object?> list => list,
    _ => map?.values ?? const [],
  };
  final byId = <String, SourceHealthRecord>{};
  for (final entry in entries) {
    final r = SourceHealthRecord.fromJson(entry);
    if (r == null) continue;
    final seen = byId[r.id];
    if (seen == null || _newer(r.probedAt, seen.probedAt)) byId[r.id] = r;
  }
  return List.unmodifiable(byId.values);
}

bool _newer(DateTime? a, DateTime? b) =>
    a != null && (b == null || a.isAfter(b));
