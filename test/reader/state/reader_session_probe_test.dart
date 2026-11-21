import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/diagnostics/upload_rule.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/reader/state/reader_session.dart';

import '../support/fakes.dart';
import 'session_fixture.dart';

/// A source whose pages call waits on [gate] to simulate a slow page
/// list fetch.
class _SlowPagesSource extends FakeSource {
  _SlowPagesSource({required this.gate, super.pageMap})
      : super(chapterList: sessionChapters);

  final Completer<void> gate;

  @override
  Future<List<PageRef>> pages(String chapterUrl) {
    return gate.future.then((_) => super.pages(chapterUrl));
  }
}

/// A source whose lookup waits on [gate] to simulate a slow source
/// lookup.
class _SlowLookupSource extends FakeSource {
  _SlowLookupSource({required this.gate, super.pageMap})
      : super(chapterList: sessionChapters);

  final Completer<void> gate;

  @override
  Future<List<ChapterInfo>> chapters(String mangaUrl) {
    return gate.future.then((_) => super.chapters(mangaUrl));
  }
}

/// The reader's probe (971debc8): a chapter that opens with no pages, or
/// whose first images all fail, sends its cause up as one `reader.open`
/// report; the screens stay as they were (icons, no text).
void main() {
  late SessionFixture f;

  setUp(() => f = SessionFixture());

  test('an online chapter with no pages is reported with its cause', () async {
    final src = FakeSource(
      chapterList: sessionChapters,
      pageMap: {'/c/2': const []},
    );
    final s = f.make(source: src);
    await s.open();
    expect(s.phase, ReaderPhase.ready, reason: 'its end leads on');
    final e = (await f.diagnostics.entries()).first;
    expect(e.kind, 'reader.open');
    expect(e.error, contains('no pages'));
    expect(e.error, contains('fake'), reason: 'the source id is the cause');
    expect(isUploadedEntry(e), isTrue);
  });

  test('when the first 3 images all fail, one report names it', () async {
    f.imageError = StateError('decode failed');
    final s = f.make();
    await s.open();
    for (var i = 0; i < 3; i++) {
      await expectLater(s.image(i), throwsStateError);
    }
    await pumpEventQueue();
    final probes = [
      for (final e in await f.diagnostics.entries())
        if (e.kind == 'reader.open') e,
    ];
    expect(probes, hasLength(1));
    expect(probes.single.error, contains('first 3 images failed'));
    expect(probes.single.error, contains('fake'));
    expect(probes.single.error, contains('decode failed'));
  });

  test('images that load keep the probe quiet', () async {
    final s = f.make();
    await s.open();
    for (var i = 0; i < 3; i++) {
      await s.image(i);
    }
    await pumpEventQueue();
    final kinds = [for (final e in await f.diagnostics.entries()) e.kind];
    expect(kinds, isNot(contains('reader.open')));
  });

  group('slow open step probe', () {
    test('a slow page list step logs the slowest step', () async {
      final gate = Completer<void>();
      final src = _SlowPagesSource(
        gate: gate,
        pageMap: {'/c/2': fakePages('/c/2', 3)},
      );

      f = SessionFixture();

      // Advance clock by 2s when 'pages' step is called
      f.onStep = (step) {
        if (step == 'pages') {
          f.advance(const Duration(seconds: 2));
        }
      };

      final s = f.make(source: src);

      // Start open - it will block on the gate
      final openFuture = s.open().timeout(const Duration(seconds: 5));

      // Wait a bit for it to reach the gate
      await Future<void>.delayed(Duration.zero);

      // Complete the gate so pages can proceed
      gate.complete();

      // Wait for open to complete
      await openFuture;

      await pumpEventQueue();

      final entries = await f.diagnostics.entries();
      final probes = [
        for (final e in entries)
          if (e.kind == 'reader.open') e,
      ];
      expect(probes, hasLength(1));
      expect(probes.single.error, contains('open waited on pages'));
      expect(probes.single.error, contains('fake'));
      expect(isUploadedEntry(probes.single), isTrue);
    });

    test('a slow source lookup step logs the slowest step', () async {
      final gate = Completer<void>();
      final src = _SlowLookupSource(
        gate: gate,
        pageMap: {'/c/2': fakePages('/c/2', 3)},
      );

      f = SessionFixture();

      // Advance clock by 2s when 'source' step is called
      f.onStep = (step) {
        if (step == 'source') {
          f.advance(const Duration(seconds: 2));
        }
      };

      final s = f.make(source: src);

      final openFuture = s.open().timeout(const Duration(seconds: 5));
      await Future<void>.delayed(Duration.zero);
      gate.complete();
      await openFuture;
      await pumpEventQueue();

      final entries = await f.diagnostics.entries();
      final probes = [
        for (final e in entries)
          if (e.kind == 'reader.open') e,
      ];
      expect(probes, hasLength(1));
      expect(probes.single.error, contains('open waited on source'));
      expect(probes.single.error, contains('fake'));
      expect(isUploadedEntry(probes.single), isTrue);
    });

    test('a fast open logs no reader.open entry', () async {
      final src = FakeSource(
        chapterList: sessionChapters,
        pageMap: {'/c/2': fakePages('/c/2', 3)},
      );

      final s = f.make(source: src);
      await s.open();

      final kinds = [for (final e in await f.diagnostics.entries()) e.kind];
      expect(kinds, isNot(contains('reader.open')));
    });
  });
}
