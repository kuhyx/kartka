import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/migration/better/better_controller.dart';

import '../fakes.dart';
import 'better_fakes.dart';

void main() {
  late BetterWorld b;

  setUp(() async {
    b = BetterWorld();
    await b.world.add('One Piece');
    await b.world.add('Berserk');
    await b.world.add('Vagabond');
    await b.world.add('Healthy', sourceId: 'fine');
    b.old.chapterLists['/One Piece'] = chaptersOf('/old/op', [1, 2]);
    b.best
      ..offer('One Piece', 'One Piece', '/best/op')
      ..offer('Berserk', 'Berserk of Gluttony', '/best/bog')
      ..chapterLists['/best/op'] = chaptersOf('/best/op', [1, 2, 3]);
    b.good
      ..offer('One Piece', 'One Piece', '/good/op')
      ..offer('Berserk', 'Berserk', '/good/b');
  });

  tearDown(() => b.world.tracking.dispose());

  Map<String, BetterRow> byTitle(BetterSourcesController c) => {
    for (final r in c.rows) r.entry.title: r,
  };

  test('suggests the highest-ranked installed keep source with the title, '
      'and skips entries already on a healthy keep source', () async {
    final c = b.controller();
    await c.load();
    expect(c.phase, BetterPhase.ready);
    final rows = byTitle(c);
    expect(rows.keys, unorderedEquals(['One Piece', 'Berserk', 'Vagabond']));
    expect(rows['One Piece']!.target?.source.ref.id, 'best');
    expect(rows['One Piece']!.match?.url, '/best/op');
    expect(rows['One Piece']!.exact, isTrue);
    expect(rows['One Piece']!.currentChapters, 2);
    expect(rows['One Piece']!.targetChapters, 3);
    expect(rows['One Piece']!.reason.label, 'its source is cut');
    // Best has only a different series: the next keep source has it.
    expect(rows['Berserk']!.target?.source.ref.id, 'good');
    expect(rows['Vagabond']!.match, isNull);
    expect(rows['Vagabond']!.searched, isTrue);
    // Searched in rank order and stopped at the first match.
    expect(
      b.best.searched,
      unorderedEquals(['One Piece', 'Berserk', 'Vagabond']),
    );
    expect(b.good.searched, unorderedEquals(['Berserk', 'Vagabond']));
    expect(b.fine.searched, ['Vagabond']);
    expect((await b.world.entries()).length, 4, reason: 'nothing moved');
  });

  test('a failing source is left too, and a search error skips that '
      'source only', () async {
    b
      ..flags['fine'] = 'Installed — test failed: empty'
      ..best.searchError = StateError('down https://best.test/?k=1');
    final c = b.controller();
    await c.load();
    final rows = byTitle(c);
    expect(rows['Healthy']!.reason.label, 'its source failed its test');
    expect(rows['One Piece']!.target?.source.ref.id, 'good');
    expect(b.fine.searched, isEmpty, reason: 'a flagged source is no target');
  });

  test('a source that is not installed is suggested away, and unknown '
      'chapter counts stay null', () async {
    b.installed = [b.best];
    final c = b.controller();
    await c.load();
    final rows = byTitle(c);
    expect(rows['One Piece']!.reason.label, 'its source is not installed');
    expect(rows['One Piece']!.currentChapters, isNull);
    b.best.chaptersError = StateError('gone');
    final again = b.controller();
    await again.load();
    expect(byTitle(again)['One Piece']!.targetChapters, isNull);
  });

  test('with no Suwayomi source listed at all (server down) its entries '
      'are not called missing', () async {
    await b.world.add('Down', sourceId: 'suwayomi:7');
    final c = b.controller();
    await c.load();
    expect(byTitle(c).containsKey('Down'), isFalse);

    b.installed = [...b.installed, ScriptedSource('suwayomi:8')];
    final listed = b.controller();
    await listed.load();
    expect(
      byTitle(listed)['Down']!.reason.label,
      'its source is not installed',
    );
  });

  test('sources nothing can install (an SY built-in, a removed extension: '
      'no record) are suggested away', () async {
    await b.world.add('Gallery', sourceId: 'sy-builtin:6901');
    await b.world.add('Batoto', sourceId: 'suwayomi:7890050626002177109');
    b.installed = [...b.installed, ScriptedSource('suwayomi:8')];
    final c = b.controller();
    await c.load();
    final rows = byTitle(c);
    expect(rows['Gallery']!.reason.label, 'its source is not installed');
    expect(rows['Batoto']!.reason.label, 'its source is not installed');
  });

  test('migrate moves one entry after a backup; migrate all moves the rest '
      'with the existing migrator', () async {
    final c = b.controller();
    await c.load();
    await c.migrate(byTitle(c)['One Piece']!);
    expect(c.backupKey, startsWith('backups/kartka-backup-'));
    expect(await b.world.backups.get(c.backupKey!), isNotNull);
    var entries = await b.world.entries();
    expect(entries.containsKey(mangaKeyOf('best', '/best/op')), isTrue);
    expect(entries.containsKey(mangaKeyOf('old', '/One Piece')), isFalse);
    expect(byTitle(c)['One Piece']!.migrated, isTrue);

    await c.migrateAll();
    expect(c.phase, BetterPhase.done);
    expect(c.migrated, 2);
    entries = await b.world.entries();
    expect(entries.containsKey(mangaKeyOf('good', '/good/b')), isTrue);
    expect(entries.containsKey(mangaKeyOf('old', '/Vagabond')), isTrue);
    expect(c.pending, 0);
  });

  test('a failed backup moves nothing and says why', () async {
    final w = World(backups: BrokenBlobStore());
    addTearDown(w.tracking.dispose);
    await w.add('One Piece');
    final c = BetterSourcesController(
      w.deps,
      BetterSourcesInputs(
        records: () async => b.records,
        sources: () async => b.installed,
      ),
    );
    await c.load();
    await c.migrateAll();
    expect(c.error, contains('disk full'));
    expect(c.migrated, 0);
    expect((await w.entries()).keys, [mangaKeyOf('old', '/One Piece')]);
  });

  test('a failed migration is counted and shown on its row', () async {
    final c = b.controller();
    await c.load();
    b.best.chaptersError = StateError('gone during migrate');
    await c.migrate(byTitle(c)['One Piece']!);
    expect(c.failed, 1);
    expect(byTitle(c)['One Piece']!.error, contains('gone during migrate'));
    expect(byTitle(c)['One Piece']!.migrated, isFalse);
  });

  test('migrate all with nothing to move does nothing', () async {
    b.installed = [];
    final c = BetterSourcesController(
      b.world.deps,
      BetterSourcesInputs(records: () async => [], sources: () async => []),
    );
    await c.load();
    await c.migrateAll();
    expect(c.backupKey, isNull);
  });
}
