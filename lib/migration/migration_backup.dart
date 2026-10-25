import 'dart:convert';

import 'package:kartka/core/models/json_fields.dart';
import 'package:kartka/migration/migration_deps.dart';
import 'package:kartka/tracking/common/track_binding.dart';

/// Writes a JSON snapshot of the whole library to `deps.backups` and
/// returns its blob key (`backups/kartka-backup-<UTC stamp>.json`).
///
/// Holds everything a migration rewrites: entries, categories, membership,
/// progress, explicit read marks and tracker bindings. Kartka had no export
/// before this, so the shape is its own (`format: kartka-backup`, v1), not
/// a .tachibk. Throws when the write fails: the caller must not migrate.
Future<String> exportBackup(MigrationDeps deps) async {
  final now = deps.clock().toUtc();
  final entries = await deps.library.watch().first;
  final membership = await deps.categories.watchMembership().first;
  final progress = <String, Object?>{};
  final marks = <String, Object?>{};
  for (final e in entries) {
    final p = await deps.progress.watch(e.key).first;
    if (p != null) progress[e.key] = p.toJson();
    final m = await deps.progress.readMarks(e.key).first;
    if (m.isNotEmpty) marks[e.key] = m;
  }
  final snapshot = {
    'format': 'kartka-backup',
    'version': 1,
    'createdAt': writeDate(now),
    'library': [for (final e in entries) e.toJson()],
    'categories': [
      for (final c in await deps.categories.watch().first) c.toJson(),
    ],
    'membership': {
      for (final m in membership.entries) m.key: m.value.toList()..sort(),
    },
    'progress': progress,
    'readMarks': marks,
    'trackers': [
      for (final b in await deps.tracking?.bindings.all() ?? <TrackBinding>[])
        b.toJson(),
    ],
  };
  final key = 'backups/kartka-backup-${_stamp(now)}.json';
  await deps.backups.put(key, utf8.encode(jsonEncode(snapshot)));
  return key;
}

String _stamp(DateTime t) {
  String two(int n) => '$n'.padLeft(2, '0');
  return '${t.year}${two(t.month)}${two(t.day)}T'
      '${two(t.hour)}${two(t.minute)}${two(t.second)}Z';
}
