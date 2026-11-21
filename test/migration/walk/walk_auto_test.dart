import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/migration/same_manga.dart';
import 'package:kartka/migration/walk/walk_auto.dart';
import 'package:kartka/migration/walk/walk_controller.dart';

import '../fakes.dart';
import 'walk_fakes.dart';

Future<(MigrationWalkController, WalkAutoPass)> _start(WalkWorld w) async {
  final c = w.controller();
  await c.load();
  return (c, WalkAutoPass(c));
}

void main() {
  test('migrates every strong match in order and stops on the first weak '
      'one, leaving it for manual review', () async {
    final w = WalkWorld();
    await w.library(['One Piece', 'Berserk', 'Vagabond', 'Monster']);
    w
      ..strong('One Piece')
      ..strong('Berserk')
      ..strong('Monster');
    final (c, auto) = await _start(w);
    await auto.run();
    expect(auto.moved, 2);
    expect(auto.running, isFalse);
    expect(c.index, 2);
    expect(c.current!.entry.title, 'Vagabond');
    expect(c.current!.found!.best.first.score, lessThan(strongMatch));
    expect(c.items.last.migratedTo, isNull);
    expect(c.backupKey, isNotNull);
  });

  test('walks to the end when every match is strong, stepping over an '
      'entry migrated by hand', () async {
    final w = WalkWorld();
    await w.library(['One Piece', 'Berserk']);
    w
      ..strong('One Piece')
      ..strong('Berserk');
    final (c, auto) = await _start(w);
    await c.current!.pending;
    await c.migrateTo(c.current!.found!.best.first);
    c.back();
    await auto.run();
    expect(auto.moved, 1);
    expect(c.current, isNull);
    expect(c.migrated, 2);
  });

  test('stop ends the pass after the migration in flight', () async {
    final w = WalkWorld();
    await w.library(['One Piece', 'Berserk']);
    w
      ..strong('One Piece')
      ..strong('Berserk');
    final (c, auto) = await _start(w);
    auto.addListener(() {
      if (auto.moved == 1) auto.stop();
    });
    await auto.run();
    expect(auto.moved, 1);
    expect(c.index, 1);
    expect(c.items[1].migratedTo, isNull);
  });

  test('a failed backup stops the pass; nothing moves', () async {
    final w = WalkWorld(backups: BrokenBlobStore());
    await w.library(['One Piece', 'Berserk']);
    w
      ..strong('One Piece')
      ..strong('Berserk');
    final (c, auto) = await _start(w);
    await auto.run();
    expect(auto.moved, 0);
    expect(c.backupError, isNotNull);
    expect(c.index, 0);
  });

  test('run twice at once runs once; a disposed pass stays quiet', () async {
    final w = WalkWorld();
    await w.library(['One Piece']);
    w.strong('One Piece');
    final (c, auto) = await _start(w);
    await Future.wait([auto.run(), auto.run()]);
    expect(auto.moved, 1);
    expect(c.current, isNull);
    auto.dispose();
    await auto.run();
  });

  test(
    'an entry not searched yet (sources still loading) stops the pass',
    () async {
      final w = WalkWorld()..sourcesGate = Completer<void>();
      await w.library(['One Piece']);
      final c = w.controller();
      final loading = c.load();
      await Future<void>.delayed(Duration.zero);
      expect(c.loaded, isTrue);
      final auto = WalkAutoPass(c);
      await auto.run();
      expect(auto.moved, 0);
      w.sourcesGate!.complete();
      await loading;
    },
  );
}
