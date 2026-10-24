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

  test('local source and SY-internal sources', () {
    expect(mapper.map('0').sourceId, 'local');
    expect(mapper.map('0').kind, SourceKind.local);
    for (final id in ['6901', '6902', '6969']) {
      final m = mapper.map(id);
      expect(m.kind, SourceKind.unmapped);
      expect(m.sourceId, 'suwayomi:$id');
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
