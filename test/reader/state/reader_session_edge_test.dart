import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/reader/data/reader_settings.dart';

import '../support/fakes.dart';
import 'session_fixture.dart';

/// The trailing slot is "on screen" only while the view reports it as the
/// current item: a neighbour laid out off screen (the paged view builds
/// one each side) is not a wait the reader sees (perf.slow 19643be5).
void main() {
  test('onTrailing follows the reported item', () async {
    final f = SessionFixture();
    await f.prefs.saveSettings(const ReaderSettings(prefetchAhead: 1));
    final source = FakeSource(
      chapterList: sessionChapters,
      pageMap: {'/c/1': fakePages('/c/1', 2), '/c/2': fakePages('/c/2', 5)},
    );
    final s = f.make(source: source);
    await s.open();
    expect(s.onTrailing, isFalse);
    s.onItem(5);
    expect(s.onTrailing, isFalse, reason: 'last page, slot off screen');
    s.onItem(6);
    expect(s.onTrailing, isTrue);
    s.onItem(5);
    expect(s.onTrailing, isFalse);
  });
}
