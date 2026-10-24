import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/backup_import/source_mapper.dart';

void main() {
  const mapper = SourceMapper();

  test('MangaDex en maps to the native source', () {
    final m = mapper.map('2499283573021220255');
    expect((m.sourceId, m.kind), ('mangadex', SourceKind.native));
  });

  test('every MangaDex language id is claimed natively', () {
    expect(mangaDexSourceIds, hasLength(mangaDexLanguages.length));
    expect(mangaDexSourceIds, contains('5098537545549490547')); // de
    expect(mangaDexSourceIds, contains('4505830566611664829')); // fr
    for (final id in mangaDexSourceIds) {
      expect(mapper.map(id).sourceId, 'mangadex');
    }
  });

  test('id formula matches a non-MangaDex source from the real backup', () {
    // Mangakakalot (en), version 1.
    expect(tachiyomiSourceId('Mangakakalot', 'en'), '2528986671771677900');
  });

  test('other ids default to suwayomi:<id>', () {
    final m = mapper.map('4709139914729853090');
    expect(m.sourceId, 'suwayomi:4709139914729853090');
    expect(m.kind, SourceKind.suwayomi);
  });

  test('local source and SY built-in sources', () {
    expect(mapper.map('0').sourceId, 'local');
    expect(mapper.map('0').kind, SourceKind.local);
    for (final id in ['6901', '6902', '6969']) {
      final m = mapper.map(id);
      expect(m.kind, SourceKind.syBuiltin);
      expect(m.sourceId, 'sy-builtin:$id');
    }
  });

  test('matches the Suwayomi cross-check of the real backup sources', () {
    final data = jsonDecode(
      File('test/fixtures/suwayomi/source_id_crosscheck.json')
          .readAsStringSync(),
    ) as Map<String, Object?>;
    for (final e in (data['matched']! as List).cast<Map<String, Object?>>()) {
      final id = e['backupSourceId']! as String;
      final suwayomi = e['suwayomi']! as Map<String, Object?>;
      final isDex = (suwayomi['pkgName']! as String).endsWith('.mangadex');
      if (isDex) {
        // Verifies the id formula for a non-English MangaDex source.
        expect(tachiyomiSourceId('MangaDex', suwayomi['lang']! as String), id);
      }
      expect(mapper.map(id).sourceId, isDex ? 'mangadex' : 'suwayomi:$id');
    }
    for (final id in (data['syBuiltin']! as List).cast<String>()) {
      expect(mapper.map(id).sourceId, 'sy-builtin:$id');
    }
    for (final id in (data['notInKeiyoushi']! as List).cast<String>()) {
      expect(mapper.map(id).sourceId, 'suwayomi:$id');
    }
  });

  test('overrides win over every default', () {
    const custom = SourceMapper(
      overrides: {'2499283573021220255': 'plugin:dex', '123': 'plugin:x'},
    );
    expect(custom.map('2499283573021220255').sourceId, 'plugin:dex');
    expect(custom.map('123').kind, SourceKind.native);
  });
}
