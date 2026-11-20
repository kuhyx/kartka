import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/updates/chapter_update_checker.dart';
import 'package:kartka/library/ports.dart';
import 'package:kartka/migration/dedupe/library_deduper.dart';
import 'package:kartka/updates/state/update_runner.dart';

import 'dedupe_fakes.dart';

void main() {
  late DedupeWorld d;

  setUp(() async {
    d = DedupeWorld();
    await d.add('good', rank: 1);
  });

  Future<void> addDuplicate() =>
      d.add('bad${d.facts.byKey.length}', authors: ['Kirihara Idumi'], rank: 9);

  test('is a library start task', () {
    expect(d.make(), isA<LibraryStartTask>());
  });

  test('start runs once, then at most every 6 h', () async {
    await addDuplicate();
    await d.make().start();
    expect(await d.w.entries(), hasLength(1));
    await addDuplicate();
    d.now = dedupeNow.add(const Duration(hours: 5));
    await d.make().start();
    expect(await d.w.entries(), hasLength(2));
    d.now = dedupeNow.add(const Duration(hours: 6));
    final again = d.make();
    await again.start();
    await again.start();
    expect(await d.w.entries(), hasLength(1));
  });

  test('runs after each library update run', () async {
    final runner = UpdateRunner(
      libraryKeys: () async => [mangaKeyOf('good', '/good')],
      check: (key) async => UpdateFound(
        key,
        chapters: const [],
        added: const [],
        firstCheck: false,
      ),
    );
    await d.local.set(dedupeLastRunKey, dedupeNow.toIso8601String());
    final deduper = d.make(updater: runner);
    await deduper.start();
    await addDuplicate();
    await runner.updateAll();
    await deduper.idle;
    expect(await d.w.entries(), hasLength(1));
  });

  test('a call during a run joins it', () async {
    await addDuplicate();
    final deduper = d.make();
    final (first, second) = await (deduper.run(), deduper.run()).wait;
    expect((first, second), (1, 1));
  });
}
