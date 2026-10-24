import 'dart:convert';

import 'package:glados/glados.dart';
import 'package:kartka/source_health/model/source_health_record.dart';

import '../fixtures.dart';
import 'record_generators.dart';

/// Removes every key of [json] (recursively, below the top level too) whose
/// position in a depth-first walk is set in [mask]. `id` always survives.
Object? dropKeys(Object? json, List<bool> mask, [List<int>? cursor]) {
  final at = cursor ?? [0];
  if (json is! Map) return json;
  final out = <String, Object?>{};
  for (final e in json.entries) {
    final i = at[0]++;
    final drop = mask.isNotEmpty && mask[i % mask.length];
    if (drop && e.key != 'id') continue;
    out[e.key as String] = dropKeys(e.value, mask, at);
  }
  return out;
}

void main() {
  Glados(any.healthRecord, ExploreConfig(numRuns: 300)).test(
    'JSON round-trip: fromJson(decode(encode(toJson(r)))) == r',
    (record) {
      final wire = jsonDecode(jsonEncode(record.toJson()));
      expect(SourceHealthRecord.fromJson(wire), record);
    },
  );

  Glados(any.healthRecord).test('toJson is a fixed point after one parse', (
    record,
  ) {
    final once = record.toJson();
    expect(SourceHealthRecord.fromJson(once)!.toJson(), once);
  });

  Glados2(any.intInRange(0, 6), any.list(any.bool)).test(
    'tolerates any subset of optional fields missing',
    (index, mask) {
      final full = fixtureMaps()[index];
      final partial = dropKeys(full, mask)! as Map<String, Object?>;
      final parsed = SourceHealthRecord.fromJson(partial)!;
      final original = SourceHealthRecord.fromJson(full)!;
      expect(parsed.id, original.id);
      // Whatever survived the drop must read exactly as in the full record.
      if (partial.containsKey('rank')) expect(parsed.rank, original.rank);
      if (partial.containsKey('score')) expect(parsed.score, original.score);
      if (partial.containsKey('verdict')) {
        expect(parsed.verdict, original.verdict);
      }
      // Re-encoding the partial record is itself round-trip stable.
      expect(SourceHealthRecord.fromJson(parsed.toJson()), parsed);
    },
  );
}
