import 'dart:convert';
import 'dart:io';

import 'package:kartka/source_health/model/source_health_record.dart';

/// Directory holding the recorded source-health fixtures.
const fixtureDir = 'test/fixtures/source_health';

/// Decoded JSON of a fixture file.
Object? fixtureJson(String name) =>
    jsonDecode(File('$fixtureDir/$name').readAsStringSync());

/// The raw record maps from `records.json`.
List<Map<String, Object?>> fixtureMaps() => [
  for (final r in fixtureJson('records.json')! as List<Object?>)
    (r! as Map).cast<String, Object?>(),
];

/// Parsed records from `records.json`.
List<SourceHealthRecord> fixtureRecords() => [
  for (final m in fixtureMaps()) SourceHealthRecord.fromJson(m)!,
];

/// The fixture record with [id].
SourceHealthRecord fixtureRecord(String id) =>
    fixtureRecords().firstWhere((r) => r.id == id);
