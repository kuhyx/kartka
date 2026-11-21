import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:kartka/core/diagnostics/upload_rule.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/source/manga_gone_error.dart';
import 'package:kartka/core/source/unknown_source_error.dart';
import 'package:kartka/core/updates/chapter_backfill.dart';
import 'package:kartka/core/updates/chapter_update_checker.dart';
import 'package:kartka/platform/memory/memory_stores.dart';

final _now = DateTime.utc(2026, 11, 21, 12);

class _Gone implements MangaGoneError;

/// Records every check; [fail] keys fail with their error.
class _Checker implements ChapterUpdateChecker {
  final calls = <MangaKey>[];
  final fail = <MangaKey, Object>{};
  int active = 0;
  int peak = 0;

  @override
  Future<UpdateResult> check(MangaKey key) async {
    calls.add(key);
    peak = max(peak, ++active);
    await Future<void>.delayed(Duration.zero);
    active--;
    final error = fail[key];
    if (error != null) return UpdateFailed(key, error);
    return UpdateFound(
      key,
      chapters: const [],
      added: const [],
      firstCheck: true,
    );
  }
}

/// An entry on its own source, added [days] after 2025-01-01.
LibraryEntry _entry(int days, {String? source}) {
  final s = source ?? 's$days';
  return LibraryEntry(
    key: mangaKeyOf(s, '/m$days'),
    sourceId: s,
    mangaUrl: '/m$days',
    title: 't$days',
    addedAt: DateTime.utc(2025).add(Duration(days: days)),
    updatedAt: DateTime.utc(2025),
  );
}

void main() {
  late _Checker checker;
  late MemoryKeyValueStore local;
  late MemoryBlobStore diag;
  late ChapterBackfill fill;

  ChapterBackfill make({ChapterUpdateChecker? using}) => ChapterBackfill(
    checker: () => using,
    local: local,
    log: DiagnosticsLog(diag),
    clock: () => _now,
  );

  setUp(() {
    checker = _Checker();
    local = MemoryKeyValueStore();
    diag = MemoryBlobStore();
    fill = make(using: checker);
  });

  test('fetches the 20 oldest, 2 at a time, and returns them', () async {
    final all = [for (var d = 24; d >= 0; d--) _entry(d)];
    final got = await fill.fill(all);
    final oldest = {for (var d = 0; d < backfillLimit; d++) _entry(d).key};
    expect(got, oldest);
    expect(checker.calls.toSet(), oldest);
    expect(checker.peak, 2);
  });

  test('one source is fetched one at a time', () async {
    await fill.fill([for (var d = 0; d < 4; d++) _entry(d, source: 'x')]);
    expect(checker.calls, hasLength(4));
    expect(checker.peak, 1);
  });

  test('a failure is skipped, logged on the device, url-free', () async {
    final bad = _entry(1);
    final gone = _entry(2);
    final unknown = _entry(3);
    checker.fail[bad.key] = StateError('500 at https://x.test/m?id=1');
    checker.fail[gone.key] = _Gone();
    checker.fail[unknown.key] = UnknownSourceError('s3');
    final got = await fill.fill([_entry(0), bad, gone, unknown]);
    expect(got, {_entry(0).key});
    final logged = await DiagnosticsLog(diag).entries();
    expect([for (final e in logged) e.kind], [backfillKind]);
    expect(logged.single.sourceId, 's1');
    expect(logged.single.error, isNot(contains('x.test')));
    expect(isUploadedEntry(logged.single), isFalse);
  });

  test('entries that failed before go last, then leave once stored', () async {
    final early = _entry(0);
    checker.fail[early.key] = StateError('boom');
    await fill.fill([early]);
    final fresh = [for (var d = 1; d <= backfillLimit; d++) _entry(d)];
    checker.calls.clear();
    await fill.fill([early, ...fresh]);
    expect(checker.calls, isNot(contains(early.key)));
    checker
      ..fail.clear()
      ..calls.clear();
    expect(await fill.fill([early]), {early.key});
    expect(await local.get(backfillTriedKey), '{}');
  });

  test('no checker or nothing missing: nothing fetched', () async {
    expect(await make().fill([_entry(0)]), isEmpty);
    expect(await fill.fill(const []), isEmpty);
    expect(checker.calls, isEmpty);
    expect(await local.get(backfillTriedKey), isNull);
  });

  test('a call while a fill runs joins it', () async {
    final first = fill.fill([_entry(0)]);
    final second = fill.fill([_entry(1)]);
    expect(await second, await first);
    expect(checker.calls, [_entry(0).key]);
  });

  test('a corrupt tried record is forgotten', () async {
    await local.set(backfillTriedKey, '[not json');
    expect(await fill.fill([_entry(0)]), {_entry(0).key});
  });

  test('knownFacts backfills the missing, then reads them again', () async {
    final known = _entry(0);
    final fetched = _entry(1);
    final dead = _entry(2);
    checker.fail[dead.key] = StateError('down');
    final stored = <MangaKey, int>{known.key: 0};
    Future<int?> of(MangaKey k) async =>
        stored[k] ?? (checker.calls.contains(k) && k == fetched.key ? 1 : null);
    final got = await knownFacts([known, fetched, dead], of, fill);
    expect(got, {known.key: 0, fetched.key: 1});
    expect(checker.calls.toSet(), {fetched.key, dead.key});
    expect(await knownFacts([known, dead], of, null), {known.key: 0});
  });
}
