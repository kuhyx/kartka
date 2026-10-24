import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/library/data/local_progress_repository.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:kartka/tracking/common/chapter_url_resolver.dart';
import 'package:kartka/tracking/common/finished_chapters.dart';

import '../fakes.dart';
import 'service_fakes.dart';

const _k = 'mangadex|/manga/abc';

class _Lookup implements ChapterUrlResolver {
  final Map<String, double> numbers = {};
  final Map<String, int> calls = {};

  @override
  Future<String?> resolve(MangaKey key, int chapterNumber) async => null;

  @override
  Future<double?> numberOf(MangaKey key, String chapterUrl) async {
    calls.update(chapterUrl, (n) => n + 1, ifAbsent: () => 1);
    return numbers[chapterUrl];
  }
}

void main() {
  late LocalProgressRepository progress;
  late _Lookup lookup;
  late List<int> seen;

  setUp(() {
    progress = LocalProgressRepository(MemoryKeyValueStore());
    lookup = _Lookup();
    seen = [];
  });

  Future<void> Function() listen({bool withLookup = true}) {
    final sub = FinishedChapters(
      () => progress,
      resolver: () => withLookup ? lookup : null,
    ).watch(_k).listen(seen.add);
    return sub.cancel;
  }

  test('opening a chapter counts nothing; finishing it counts', () async {
    final cancel = listen();
    await progress.record(progressAt(_k, 3, page: 5));
    await pumpEvents();
    expect(seen, isEmpty);
    await progress.markRead(_k, '/chapter/3.0');
    await pumpEvents();
    await cancel();
    expect(seen.last, 3);
  });

  test('the count is the floor of the highest finished chapter', () async {
    lookup.numbers.addAll({'/a': 10.5, '/b': 2});
    final cancel = listen();
    await progress.markRead(_k, '/b');
    await progress.markRead(_k, '/a');
    await pumpEvents();
    await cancel();
    expect(seen.last, 10);
  });

  test('unread tombstones and unknown numbers do not count', () async {
    lookup.numbers.addAll({'/a': 4, '/b': 9});
    final cancel = listen();
    await progress.markRead(_k, '/a');
    await progress.markRead(_k, '/b');
    await progress.markUnread(_k, '/b');
    await progress.markRead(_k, '/unknown');
    await pumpEvents();
    await cancel();
    expect(seen.last, 4);
  });

  test('without any lookup only progress-learned numbers count', () async {
    final cancel = listen(withLookup: false);
    await progress.markRead(_k, '/chapter/7.0');
    await pumpEvents();
    expect(seen, isEmpty);
    await progress.record(progressAt(_k, 7));
    await pumpEvents();
    await cancel();
    expect(seen.last, 7);
  });

  test('a number learned once is not looked up again', () async {
    lookup.numbers['/a'] = 4;
    final cancel = listen();
    await progress.markRead(_k, '/a');
    await pumpEvents();
    await progress.markRead(_k, '/x');
    await pumpEvents();
    await cancel();
    expect(lookup.calls['/a'], 1);
    expect(lookup.calls['/x'], greaterThanOrEqualTo(1));
  });

  test('repository errors reach the stream', () async {
    final errors = <Object>[];
    final sub = FinishedChapters(
      () => throw StateError('no repo'),
      resolver: () => null,
    ).watch(_k).listen((_) {}, onError: errors.add);
    await pumpEvents();
    await sub.cancel();
    expect(errors.single, isA<StateError>());
  });

  test('current() counts once, null when nothing is finished', () async {
    final counter = FinishedChapters(() => progress, resolver: () => lookup);
    expect(await counter.current(_k), isNull);
    await progress.record(progressAt(_k, 6));
    await progress.markRead(_k, '/chapter/6.0');
    expect(await counter.current(_k), 6);
  });
}
