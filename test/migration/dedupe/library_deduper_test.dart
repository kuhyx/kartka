import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:kartka/core/diagnostics/upload_rule.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/migration/dedupe/library_deduper.dart';
import 'package:kartka/tracking/common/track_binding.dart';

import '../fakes.dart';
import 'dedupe_fakes.dart';

void main() {
  late DedupeWorld d;

  setUp(() => d = DedupeWorld());

  test('the screenshot case merges onto the better-ranked source', () async {
    final good = await d.add('good', rank: 2);
    final bad = await d.add(
      'bad',
      authors: ['Kirihara Idumi'],
      read: 12,
      rank: 9,
      added: DateTime.utc(2024),
    );
    await d.w.repos.categories.setMembership(bad.key, 'romance', true);
    await d.w.repos.categories.setMembership(good.key, 'shelf', true);
    await d.w.repos.progress.record(
      ReadingProgress(
        key: bad.key,
        chapterUrl: 'bad/12',
        chapterNumber: 12,
        page: 3,
        readAt: DateTime.utc(2025, 3),
      ),
    );

    expect(await d.make().run(), 1);

    final left = await d.w.entries();
    expect(left.keys, [good.key]);
    expect(left[good.key]!.addedAt, DateTime.utc(2024));
    expect(await d.readOf(good), {for (var n = 1; n <= 12; n++) 'good/$n'});
    expect(await d.categoriesOf(good), {'romance', 'shelf'});
    expect(await d.categoriesOf(bad), isEmpty);
    final p = await d.w.repos.progress.watch(good.key).first;
    expect((p!.chapterUrl, p.page), ('good/12', 3));
  });

  test('the same title by another author is not merged', () async {
    await d.add('a', authors: ['Mori Aya'], rank: 1);
    await d.add('b', authors: ['Kirihara Idumi'], rank: 2);
    expect(await d.make().run(), 0);
    expect(await d.w.entries(), hasLength(2));
  });

  test('chapter counts far apart are not merged', () async {
    await d.add('a', authors: ['Kirihara Idumi'], rank: 1);
    await d.add('b', authors: ['Kirihara Idumi'], count: 40, rank: 2);
    expect(await d.make().run(), 0);
    expect(await d.w.entries(), hasLength(2));
  });

  test('a pair with no author and no description is skipped', () async {
    await d.add('a', rank: 1);
    await d.add('b', rank: 2);
    expect(await d.make().run(), 0);
    expect(await d.w.entries(), hasLength(2));
    expect(await d.backups(), isEmpty);
  });

  test('one backup holding the loser is written before the delete', () async {
    await d.add('good', rank: 1);
    final bad = await d.add('bad', authors: ['Kirihara Idumi'], rank: 2);
    await d.make().run();
    final blobs = await d.backups();
    expect(blobs, hasLength(1));
    final raw = await d.w.backups.get(blobs.single);
    final snapshot = jsonDecode(utf8.decode(raw!)) as Map<String, Object?>;
    final keys = [
      for (final e in snapshot['library']! as List<Object?>)
        (e! as Map<String, Object?>)['key'],
    ];
    expect(keys, contains(bad.key));
  });

  test('a failed backup merges nothing', () async {
    d = DedupeWorld(world: World(backups: BrokenBlobStore()));
    await d.add('good', rank: 1);
    await d.add('bad', authors: ['Kirihara Idumi'], rank: 2);
    await expectLater(d.make().run(), throwsStateError);
    expect(await d.w.entries(), hasLength(2));
  });

  test('a second run merges nothing and writes no backup', () async {
    await d.add('good', rank: 1);
    await d.add('bad', authors: ['Kirihara Idumi'], rank: 2);
    final deduper = d.make();
    expect(await deduper.run(), 1);
    expect(await deduper.run(), 0);
    expect(await d.backups(), hasLength(1));
  });

  test('a three-way duplicate collapses onto the best source', () async {
    final best = await d.add('a', authors: ['Kirihara Idumi'], rank: 1);
    await d.add('b', read: 5, rank: 2);
    await d.add('c', authors: ['Idumi Kirihara'], count: 13, read: 13, rank: 3);
    expect(await d.make().run(), 2);
    expect((await d.w.entries()).keys, [best.key]);
    expect(await d.readOf(best), {for (var n = 1; n <= 12; n++) 'a/$n'});
  });

  test('an entry whose source is not installed loses', () async {
    await d.add('gone', rank: 1);
    final here = await d.add('here', authors: ['Kirihara Idumi'], rank: 5);
    d.installed.remove('gone');
    expect(await d.make().run(), 1);
    expect((await d.w.entries()).keys, [here.key]);
  });

  test('without a ranking or installed sources it does nothing', () async {
    await d.add('good', rank: 1);
    await d.add('bad', authors: ['Kirihara Idumi'], rank: 2);
    final health = d.health;
    d.health = null;
    expect(await d.make().run(), 0);
    d
      ..health = health
      ..installed = {};
    expect(await d.make().run(), 0);
    expect(await d.w.entries(), hasLength(2));
    expect(await d.local.get(dedupeLastRunKey), isNull);
  });

  test('moves a tracker binding the winner lacks, drops the rest', () async {
    final good = await d.add('good', rank: 1);
    final bad = await d.add('bad', authors: ['Kirihara Idumi'], rank: 2);
    final bindings = d.w.bindings;
    await bindings.put(
      TrackBinding(key: bad.key, service: 'mal', remoteId: '1'),
    );
    await bindings.put(
      TrackBinding(key: bad.key, service: 'anilist', remoteId: '2'),
    );
    await bindings.put(
      TrackBinding(key: good.key, service: 'anilist', remoteId: '3'),
    );
    await d.make().run();
    final all = {
      for (final b in await bindings.all()) (b.key, b.service): b.remoteId,
    };
    expect(all, {(good.key, 'mal'): '1', (good.key, 'anilist'): '3'});
  });

  test('logs one device-only counts line when it merged', () async {
    await d.add('good', rank: 1);
    await d.add('bad', authors: ['Kirihara Idumi'], rank: 2);
    await d.make().run();
    await d.make().run();
    final logged = await DiagnosticsLog(d.diag).entries();
    expect([for (final e in logged) e.kind], [dedupeKind]);
    expect(logged.single.error, 'merged 1 into 1');
    expect(isUploadedEntry(logged.single), isFalse);
  });
}
