import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/migration/migration_controller.dart';
import 'package:kartka/migration/migration_target.dart';

import 'fakes.dart';

void main() {
  late World w;

  setUp(() async {
    w = World()..install();
    await w.add('One Piece');
    await w.add('Berserk');
    await w.add('Vagabond');
    await w.add('Already', sourceId: atsumaruSourceId);
    w.target
      ..offer('One Piece', 'one piece ', '/atsu/op')
      ..offer('Berserk', 'Berserk: Deluxe', '/atsu/b')
      ..offer('Berserk', 'Berserk', '/atsu/b2');
  });

  tearDown(() => w.tracking.dispose());

  Map<String, MigrationRow> byTitle(MigrationController c) => {
    for (final r in c.rows) r.entry.title: r,
  };

  test('exact title matches are pre-ticked, others shown unticked', () async {
    final c = MigrationController(w.deps);
    await c.load();
    expect(c.phase, MigrationPhase.ready);
    final rows = byTitle(c);
    expect(rows.keys, unorderedEquals(['One Piece', 'Berserk', 'Vagabond']));
    expect(rows['One Piece']!.ticked, isTrue);
    expect(rows['One Piece']!.exact, isTrue);
    // An exact match further down the results wins over the first result.
    expect(rows['Berserk']!.candidate?.url, '/atsu/b2');
    expect(rows['Berserk']!.ticked, isTrue);
    expect(rows['Vagabond']!.candidate, isNull);
    expect(rows['Vagabond']!.ticked, isFalse);
    // Searched one at a time, never the entry already on Atsumaru.
    expect(w.target.searched, isNot(contains('Already')));
  });

  test('a non-exact best match is shown unticked', () async {
    w.target.offer('Vagabond', 'Vagabond (Colour)', '/atsu/v');
    final c = MigrationController(w.deps);
    await c.load();
    final v = byTitle(c)['Vagabond']!;
    expect(v.candidate?.title, 'Vagabond (Colour)');
    expect(v.exact, isFalse);
    expect(v.ticked, isFalse);
    c.setTicked(v, ticked: true);
    expect(v.ticked, isTrue);
  });

  test('a failed search leaves the row unticked with the error', () async {
    w.target.searchError = StateError('down https://atsu.test/?k=SECRET');
    final c = MigrationController(w.deps);
    await c.load();
    final r = byTitle(c)['One Piece']!;
    expect(r.ticked, isFalse);
    expect(r.error, contains('down'));
    expect(r.error, isNot(contains('SECRET')));
    // A row without a candidate cannot be ticked.
    c.setTicked(r, ticked: true);
    expect(r.ticked, isFalse);
    expect(c.canApply, isFalse);
  });

  test('only the given keys are reviewed', () async {
    final key = mangaKeyOf('old', '/Berserk');
    final c = MigrationController(w.deps, onlyKeys: {key});
    await c.load();
    expect(c.rows.map((r) => r.entry.key), [key]);
  });

  test('no Atsumaru source: unavailable, nothing searched', () async {
    w.lookup = () => null;
    final c = MigrationController(w.deps);
    await c.load();
    expect(c.phase, MigrationPhase.unavailable);
    expect(c.canApply, isFalse);
    expect(w.target.searched, isEmpty);
  });

  test('loading alone changes nothing and writes no backup', () async {
    final before = await w.entries();
    final c = MigrationController(w.deps);
    await c.load();
    expect(c.canApply, isTrue);
    expect(await w.entries(), before);
    expect(await w.backups.list('backups'), isEmpty);
  });

  test('apply exports a backup of the old state first', () async {
    final c = MigrationController(w.deps);
    await c.load();
    await c.apply();
    expect(c.phase, MigrationPhase.done);
    expect(c.migrated, 2);
    expect(c.backupKey, 'backups/kartka-backup-20261025T123005Z.json');
    final backup = jsonDecode(
      utf8.decode((await w.backups.get(c.backupKey!))!),
    ) as Map<String, Object?>;
    final titles = [
      for (final e in backup['library']! as List<Object?>)
        (e! as Map<String, Object?>)['title'],
    ];
    // Taken before any write: the old entries, none of the new ones.
    expect(
      titles,
      unorderedEquals(['One Piece', 'Berserk', 'Vagabond', 'Already']),
    );
    final now = await w.entries();
    expect(now.values.map((e) => e.mangaUrl), contains('/atsu/op'));
    expect(now.values.map((e) => e.title), contains('Vagabond'));
    expect(now.keys, isNot(contains(mangaKeyOf('old', '/One Piece'))));
  });

  test('a failed backup stops the apply before any write', () async {
    w = World(backups: BrokenBlobStore())..install();
    await w.add('One Piece');
    w.target.offer('One Piece', 'One Piece', '/atsu/op');
    final c = MigrationController(w.deps);
    await c.load();
    final before = await w.entries();
    await c.apply();
    expect(c.phase, MigrationPhase.failed);
    expect('${c.error}', contains('disk full'));
    expect(await w.entries(), before);
  });

  test('a failing entry is counted, the rest still move', () async {
    final c = MigrationController(w.deps);
    await c.load();
    w.target.chaptersError = StateError('gone');
    await c.apply();
    expect(c.phase, MigrationPhase.done);
    expect(c.migrated, 0);
    expect(c.failed, 2);
    expect(byTitle(c)['Berserk']!.error, contains('gone'));
  });
}
