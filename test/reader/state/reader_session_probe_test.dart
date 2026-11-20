import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/diagnostics/upload_rule.dart';
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
}
