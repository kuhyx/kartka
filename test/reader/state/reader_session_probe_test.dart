import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/diagnostics/diagnostic_entry.dart';
import 'package:kartka/core/diagnostics/upload_rule.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/reader/state/reader_session.dart';

import '../support/fakes.dart';
import 'session_fixture.dart';

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
    test('a slow page list names pages', () async {
      final s = f.make(source: _SlowPages(f, const Duration(seconds: 2)));
      await s.open();
      final probes = await _probes(f);
      expect(probes, hasLength(1));
      expect(probes.single.error, contains('open waited on pages'));
      expect(probes.single.error, contains('fake'));
      expect(isUploadedEntry(probes.single), isTrue);
    });

    test('a slow source lookup names source', () async {
      final src = FakeSource(
        chapterList: sessionChapters,
        pageMap: {'/c/2': fakePages('/c/2', 3)},
      );
      final s = f.make(
        source: src,
        findSource: (id) async {
          await Future<void>.delayed(Duration.zero);
          f.clock = f.clock.add(const Duration(seconds: 3));
          return src;
        },
      );
      await s.open();
      final probes = await _probes(f);
      expect(probes, hasLength(1));
      expect(probes.single.error, contains('open waited on source'));
    });

    test('an open under 1 s logs no probe', () async {
      final s = f.make(
        source: _SlowPages(f, const Duration(milliseconds: 900)),
      );
      await s.open();
      expect(await _probes(f), isEmpty);
    });
  });
}

/// A source whose page list takes [delay] on the fixture's clock.
class _SlowPages extends FakeSource {
  new(this.f, this.delay)
    : super(
        chapterList: sessionChapters,
        pageMap: {'/c/2': fakePages('/c/2', 3)},
      );

  final SessionFixture f;
  final Duration delay;

  @override
  Future<List<PageRef>> pages(String chapterUrl) {
    f.clock = f.clock.add(delay);
    return super.pages(chapterUrl);
  }
}

Future<List<DiagnosticEntry>> _probes(SessionFixture f) =>
    f.diagnostics.entries().then(
      (entries) => [
        for (final e in entries)
          if (e.kind == 'reader.open') e,
      ],
    );
