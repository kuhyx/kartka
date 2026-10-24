import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/reader/data/reader_settings.dart';
import 'package:kartka/reader/logic/reader_mode.dart';
import 'package:kartka/reader/logic/tap_zones.dart';

void main() {
  test('defaults', () {
    const s = ReaderSettings();
    expect(s.defaultMode, ReaderMode.pagedRtl);
    expect(s.prefetchAhead, 3);
    expect(s.tapLayout, TapZoneLayout.thirds);
    expect(s.invertTaps, isFalse);
  });

  test('json round-trip', () {
    const s = ReaderSettings(
      defaultMode: ReaderMode.webtoon,
      prefetchAhead: 7,
      tapLayout: TapZoneLayout.kindle,
      invertTaps: true,
    );
    expect(ReaderSettings.fromJson(s.toJson()), s);
    expect(ReaderSettings.fromJson(s.toJson()).hashCode, s.hashCode);
  });

  test('bad or missing json falls back to defaults and clamps prefetch', () {
    expect(ReaderSettings.fromJson(const {}), const ReaderSettings());
    expect(
      ReaderSettings.fromJson(const {
        'defaultMode': 'x',
        'prefetchAhead': 'many',
        'tapLayout': 3,
        'invertTaps': 'yes',
      }),
      const ReaderSettings(),
    );
    expect(
      ReaderSettings.fromJson(const {'prefetchAhead': 99}).prefetchAhead,
      ReaderSettings.maxPrefetch,
    );
    expect(
      ReaderSettings.fromJson(const {'prefetchAhead': -2}).prefetchAhead,
      0,
    );
  });

  test('copyWith changes only the given fields', () {
    const s = ReaderSettings();
    final c = s.copyWith(prefetchAhead: 50, invertTaps: true);
    expect(c.prefetchAhead, ReaderSettings.maxPrefetch);
    expect(c.invertTaps, isTrue);
    expect(c.defaultMode, s.defaultMode);
    expect(
      s.copyWith(
        defaultMode: ReaderMode.webtoon,
        tapLayout: TapZoneLayout.lShape,
      ),
      const ReaderSettings(
        defaultMode: ReaderMode.webtoon,
        tapLayout: TapZoneLayout.lShape,
      ),
    );
    expect(s.copyWith(), s);
    expect(s, isNot(c));
  });
}
