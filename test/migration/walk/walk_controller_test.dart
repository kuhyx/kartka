import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/migration/walk/walk_controller.dart';
import 'package:kartka/source_health/model/source_health_record.dart';

import '../fakes.dart';
import 'walk_fakes.dart';

Future<void> _settle(MigrationWalkController c) async {
  for (final i in c.items) {
    await i.pending;
  }
}

void main() {
  test('walks the library in order, searching the current entry and the '
      'next one only', () async {
    final w = WalkWorld();
    await w.library(['One Piece', 'Berserk', 'Vagabond']);
    final c = w.controller();
    await c.load();
    await _settle(c);
    expect(
      [for (final i in c.items) i.entry.title],
      ['One Piece', 'Berserk', 'Vagabond'],
    );
    expect(w.best.searched, ['One Piece', 'Berserk']);
    expect(c.current!.found!.best.first.manga.url, '/best/One Piece');
    expect(c.current!.sourceName, 'Old Site');
    c.skip();
    await _settle(c);
    expect(w.best.searched, ['One Piece', 'Berserk', 'Vagabond']);
    c.back();
    expect(c.index, 0);
    c.back();
    expect(c.index, 0);
  });

  test(
    'a card migrates the entry (one backup per session) and advances',
    () async {
      final w = WalkWorld();
      await w.library(['One Piece', 'Berserk']);
      final c = w.controller();
      await c.load();
      await _settle(c);
      await c.migrateTo(c.current!.found!.best.first);
      expect(c.index, 1);
      expect(c.backupKey, 'backups/kartka-backup-20261025T123005Z.json');
      await _settle(c);
      await c.migrateTo(c.current!.found!.best.first);
      expect(c.current, isNull);
      expect(c.migrated, 2);
      expect(await w.world.backups.list('backups/'), hasLength(1));
      final urls = (await w.world.entries()).values.map((e) => e.mangaUrl);
      expect(urls, unorderedEquals(['/best/One Piece', '/best/Berserk']));
      // Going back to a migrated entry cannot migrate it twice.
      c.back();
      await c.migrateTo(c.items.first.found!.best.first);
      expect(c.migrated, 2);
    },
  );

  test('a failed backup changes nothing and stays on the entry', () async {
    final broken = WalkWorld(backups: BrokenBlobStore());
    await broken.library(['One Piece']);
    final c = broken.controller();
    await c.load();
    await _settle(c);
    await c.migrateTo(c.current!.found!.best.first);
    expect(c.backupError, contains('disk full'));
    expect(c.index, 0);
    expect((await broken.world.entries()).keys, [
      mangaKeyOf('old', '/One Piece'),
    ]);
  });

  test('a failed migration is kept on the entry', () async {
    final w = WalkWorld();
    await w.library(['One Piece']);
    final c = w.controller();
    await c.load();
    await _settle(c);
    w.best.chaptersError = StateError('gone');
    await c.migrateTo(c.current!.found!.best.first);
    expect(c.index, 0);
    expect(c.failed, 1);
    expect(c.current!.error, contains('gone'));
  });

  test('better scope walks only entries whose source should be left; '
      'onlyKeys walks just those', () async {
    final w = WalkWorld();
    await w.library(['One Piece']);
    await w.world.add('Fine', sourceId: 'good');
    final better = w.controller(scope: WalkScope.better);
    await better.load();
    expect([for (final i in better.items) i.entry.title], ['One Piece']);
    final one = w.controller(onlyKeys: {mangaKeyOf('good', '/Fine')});
    await one.load();
    expect([for (final i in one.items) i.entry.title], ['Fine']);
  });

  test(
    'a manual search replaces the candidates of the current entry',
    () async {
      final w = WalkWorld();
      await w.library(['One Piece']);
      w.good.offer('Wan Pisu', 'Wan Pisu', '/good/wp');
      final c = w.controller();
      await c.load();
      c
        ..search('  ')
        ..search('Wan Pisu');
      await _settle(c);
      expect(w.good.searched, contains('Wan Pisu'));
      expect(
        c.current!.found!.best.map((m) => m.manga.url),
        contains('/good/wp'),
      );
    },
  );

  test(
    'better scope also walks entries on a source rejected for good',
    () async {
      final w = WalkWorld();
      await w.world.add('Fine', sourceId: 'good');
      await w.world.add('Gone', sourceId: 'gone');
      // Installed, its record deleted with the rejection.
      w
        ..rejected = const {'gone'}
        ..installed = [...w.installed, ScriptedSource('gone')];
      final c = w.controller(scope: WalkScope.better);
      await c.load();
      expect([for (final i in c.items) i.entry.title], ['Gone']);
    },
  );

  test('with no keep source, the best-ranked other installed sources are '
      'searched', () async {
    final w = WalkWorld();
    await w.library(['One Piece']);
    final weeb = ScriptedSource('weeb', name: 'Weeb Central')
      ..offer('One Piece', 'One Piece', '/weeb/op');
    w
      ..records = const [
        SourceHealthRecord(
          id: 'weeb',
          name: 'Weeb Central',
          rank: 4,
          verdict: HealthVerdict.cut,
        ),
      ]
      ..installed = [w.old, weeb];
    final c = w.controller();
    await c.load();
    await _settle(c);
    expect(c.current!.found!.best.single.manga.url, '/weeb/op');
  });

  test('the first entry shows before the source list settles', () async {
    final w = WalkWorld();
    await w.library(['One Piece']);
    final gate = w.sourcesGate = Completer<void>();
    final c = w.controller();
    final loading = c.load();
    await pumpEventQueue();
    expect(c.loaded, isTrue);
    expect(c.current!.entry.title, 'One Piece');
    gate.complete();
    await loading;
    await _settle(c);
    expect(c.current!.found!.best, isNotEmpty);
  });

  test(
    'lanes fill as they arrive: a slow source does not hide the others',
    () async {
      final w = WalkWorld();
      await w.library(['One Piece']);
      w.good.offer('One Piece', 'One Piece', '/good/op');
      final slow = w.best.gate = Completer<void>();
      final c = w.controller();
      await c.load();
      await pumpEventQueue();
      final partial = c.current!.found!;
      expect(
        {for (final l in partial.lanes) l.source.ref.id: l.state},
        {'best': LaneState.searching, 'good': LaneState.found},
      );
      expect(partial.best.single.manga.url, '/good/op');
      slow.complete();
      await _settle(c);
      expect(c.current!.found!.best, hasLength(2));
    },
  );
}
