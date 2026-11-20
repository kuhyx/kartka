import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:kartka/core/diagnostics/upload_rule.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/updates/chapter_update_checker.dart';
import 'package:kartka/library/library_repositories.dart';
import 'package:kartka/library/ports.dart';
import 'package:kartka/library/state/auto_shelver.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/updates/state/update_runner.dart';

import '../support/fakes.dart';

/// Pinned "now" of every test: 2026-11-21 12:00 UTC.
final _now = DateTime.utc(2026, 11, 21, 12);

class _Facts implements ShelfFactsLookup {
  final Map<MangaKey, ShelfFacts?> byKey = {};

  @override
  Future<ShelfFacts?> of(MangaKey key) async => byKey[key];
}

void main() {
  late MemoryKeyValueStore kv;
  late MemoryKeyValueStore memory;
  late MemoryBlobStore diag;
  late LibraryRepositories repos;
  late _Facts facts;
  late DateTime now;
  late AutoShelver shelver;
  final a = entry('/a');
  final b = entry('/b');

  AutoShelver make({LibraryUpdater? updater}) => AutoShelver(
    repos: repos,
    facts: () => facts,
    memory: memory,
    local: kv,
    updater: () => updater,
    log: DiagnosticsLog(diag),
    clock: () => now,
  );

  setUp(() async {
    kv = MemoryKeyValueStore();
    memory = MemoryKeyValueStore();
    diag = MemoryBlobStore();
    now = _now;
    repos = LibraryRepositories(kv, decorators: () => [], now: () => now);
    facts = _Facts();
    shelver = make();
    await repos.library.upsert(a);
    await repos.library.upsert(b);
  });

  Future<void> cat(String id, String name, int order) => repos.categories
      .upsert(Category(id: id, name: name, order: order, updatedAt: t0));
  Future<Set<String>> member(LibraryEntry e) async =>
      (await repos.categories.watchMembership().first)[e.key] ?? const {};
  Future<List<String>> names() async => [
    for (final c in await repos.categories.watch().first) c.name,
  ];
  ShelfFacts fact(DateTime? newest, {bool allRead = true}) =>
      (newestUpload: newest, allRead: allRead);
  final old = DateTime.utc(2024, 6, 26);

  test('stale and all read: moved to the existing "Finished" only', () async {
    await cat('c1', '1', 0);
    await cat('fin', ' Finished ', 1);
    await repos.categories.setMembership(a.key, 'c1', true);
    facts.byKey[a.key] = fact(old);
    expect(await shelver.run(), (finished: 1, abandoned: 0));
    expect(await member(a), {'fin'});
    expect(await member(b), isEmpty);
  });

  test('stale with unread: reuses a Completed/Abandoned category', () async {
    await cat('x', 'finished', 0);
    await cat('ab', 'Completed/Abandoned', 1);
    await cat('ab2', 'abandoned too', 2);
    facts.byKey[a.key] = fact(old, allRead: false);
    expect(await shelver.run(), (finished: 0, abandoned: 1));
    expect(await member(a), {'ab'});
  });

  test('targets absent: "finished" and "abandoned" are created', () async {
    await cat('c8', '8', 0);
    facts.byKey[a.key] = fact(old);
    facts.byKey[b.key] = fact(old, allRead: false);
    await shelver.run();
    expect(await names(), ['8', 'finished', 'abandoned']);
    expect(await member(a), {autoShelfId(Shelf.finished)});
    expect(await member(b), {autoShelfId(Shelf.abandoned)});
  });

  test('17 months old, undated or unknown: untouched', () async {
    facts.byKey[a.key] = fact(DateTime.utc(2025, 6, 22));
    facts.byKey[b.key] = fact(null);
    expect(await shelver.run(), (finished: 0, abandoned: 0));
    expect(await member(a), isEmpty);
    expect(await member(b), isEmpty);
    expect(await names(), isEmpty);
    expect(await DiagnosticsLog(diag).entries(), isEmpty);
  });

  test('the cutoff is 18 calendar months, day clamped', () {
    expect(staleCutoff(_now), DateTime.utc(2025, 5, 21, 12));
    expect(staleCutoff(DateTime.utc(2026, 8, 31)), DateTime.utc(2025, 2, 28));
    expect(isStale(DateTime.utc(2025, 5, 21, 12), _now), isFalse);
    expect(isStale(DateTime.utc(2025, 5, 21, 11), _now), isTrue);
  });

  test('a manual move-out is not undone while no chapter is new', () async {
    await cat('fin', 'finished', 0);
    await cat('c1', '1', 1);
    facts.byKey[a.key] = fact(old);
    await shelver.run();
    await repos.categories.setMembership(a.key, 'fin', false);
    await repos.categories.setMembership(a.key, 'c1', true);
    expect(await make().run(), (finished: 0, abandoned: 0));
    expect(await member(a), {'c1'});
  });

  test('a new chapter resets the memory', () async {
    await cat('fin', 'finished', 0);
    facts.byKey[a.key] = fact(old);
    await shelver.run();
    await repos.categories.setMembership(a.key, 'fin', false);
    facts.byKey[a.key] = fact(DateTime.utc(2026, 11));
    await shelver.run();
    expect(await member(a), isEmpty);
    now = DateTime.utc(2028, 6);
    expect(await shelver.run(), (finished: 1, abandoned: 0));
    expect(await member(a), {'fin'});
  });

  test('already in the target: left alone, yet remembered', () async {
    await cat('fin', 'finished', 0);
    await cat('c1', '1', 1);
    await repos.categories.setMembership(a.key, 'fin', true);
    await repos.categories.setMembership(a.key, 'c1', true);
    facts.byKey[a.key] = fact(old);
    expect(await shelver.run(), (finished: 0, abandoned: 0));
    expect(await member(a), {'fin', 'c1'});
    // Another device moved it; kuhy then took it out by hand.
    await repos.categories.setMembership(a.key, 'fin', false);
    await shelver.run();
    expect(await member(a), {'c1'});
  });

  test('logs one counts-only line when it moved something', () async {
    facts.byKey[a.key] = fact(old);
    facts.byKey[b.key] = fact(old, allRead: false);
    await shelver.run();
    await shelver.run();
    final logged = await DiagnosticsLog(diag).entries();
    expect([for (final e in logged) e.kind], [autoShelveKind]);
    expect(logged.single.error, 'moved 2: finished 1, abandoned 1');
    expect(isUploadedEntry(logged.single), isFalse);
  });

  test('start runs once, then at most every 6 h', () async {
    facts.byKey[a.key] = fact(old);
    await shelver.start();
    expect(await member(a), hasLength(1));
    await repos.categories.setMembership(
      a.key,
      autoShelfId(Shelf.finished),
      false,
    );
    await memory.remove(autoShelveMemoryKey);
    now = _now.add(const Duration(hours: 5));
    await make().start();
    expect(await member(a), isEmpty);
    now = _now.add(const Duration(hours: 6));
    final again = make();
    await again.start();
    await again.start();
    expect(await member(a), hasLength(1));
  });

  test('runs after each library update run', () async {
    final runner = UpdateRunner(
      libraryKeys: () async => [a.key],
      check: (key) async {
        facts.byKey[key] = fact(old, allRead: false);
        return UpdateFound(
          key,
          chapters: const [],
          added: const [],
          firstCheck: false,
        );
      },
    );
    now = _now.add(const Duration(hours: 1));
    await kv.set(autoShelveLastRunKey, _now.toIso8601String());
    final s = make(updater: runner);
    await s.start();
    expect(await member(a), isEmpty);
    await runner.updateAll();
    await s.idle;
    expect(await member(a), {autoShelfId(Shelf.abandoned)});
  });

  test('a device that cannot judge an entry keeps its memory', () async {
    await cat('fin', 'finished', 0);
    facts.byKey[a.key] = fact(old);
    await shelver.run();
    // Device B shares the synced memory but never stored a's chapters.
    final blind = AutoShelver(
      repos: repos,
      facts: _Facts.new,
      memory: memory,
      local: MemoryKeyValueStore(),
      updater: () => null,
    );
    await blind.run();
    await repos.categories.setMembership(a.key, 'fin', false);
    expect(await make().run(), (finished: 0, abandoned: 0));
    expect(await member(a), isEmpty);
  });

  test('an older stored list does not reset the memory', () async {
    await cat('fin', 'finished', 0);
    facts.byKey[a.key] = fact(old);
    await shelver.run();
    await repos.categories.setMembership(a.key, 'fin', false);
    facts.byKey[a.key] = fact(DateTime.utc(2024, 5));
    expect(await shelver.run(), (finished: 0, abandoned: 0));
    expect(await member(a), isEmpty);
    expect(await memory.get(autoShelveMemoryKey), contains('2024-06-26'));
  });

  test('a corrupt memory forgets; a renamed rule shelf is reused', () async {
    await cat(autoShelfId(Shelf.finished), 'Done', 0);
    await memory.set(autoShelveMemoryKey, '{not json');
    facts.byKey[a.key] = fact(old);
    expect(await shelver.run(), (finished: 1, abandoned: 0));
    expect(await names(), ['Done']);
    expect(await memory.get(autoShelveMemoryKey), contains(a.key));
  });
}
