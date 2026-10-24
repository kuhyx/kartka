import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/reader/logic/reader_mode.dart';
import 'package:kartka/reader/logic/tap_zones.dart';

void main() {
  const size = Size(300, 300);
  TapAction tap(
    TapZoneLayout layout,
    double x,
    double y, {
    ReaderMode mode = ReaderMode.pagedLtr,
    bool invert = false,
  }) => resolveTap(
    layout: layout,
    position: Offset(x, y),
    size: size,
    mode: mode,
    invert: invert,
  );

  test('thirds: left previous, right next, middle menu (LTR)', () {
    expect(tap(TapZoneLayout.thirds, 10, 150), TapAction.previous);
    expect(tap(TapZoneLayout.thirds, 290, 150), TapAction.next);
    expect(tap(TapZoneLayout.thirds, 150, 150), TapAction.menu);
  });

  test('RTL mirrors the sides, vertical modes do not', () {
    expect(
      tap(TapZoneLayout.thirds, 10, 150, mode: ReaderMode.pagedRtl),
      TapAction.next,
    );
    expect(
      tap(TapZoneLayout.thirds, 10, 150, mode: ReaderMode.webtoon),
      TapAction.previous,
    );
  });

  test('invert swaps previous and next but never the menu', () {
    expect(tap(TapZoneLayout.thirds, 10, 150, invert: true), TapAction.next);
    expect(
      tap(TapZoneLayout.thirds, 290, 150, invert: true),
      TapAction.previous,
    );
    expect(tap(TapZoneLayout.thirds, 150, 150, invert: true), TapAction.menu);
  });

  test('lShape: top band and left column go back', () {
    expect(tap(TapZoneLayout.lShape, 290, 10), TapAction.previous);
    expect(tap(TapZoneLayout.lShape, 10, 150), TapAction.previous);
    expect(tap(TapZoneLayout.lShape, 10, 290), TapAction.next);
    expect(tap(TapZoneLayout.lShape, 290, 150), TapAction.next);
    expect(tap(TapZoneLayout.lShape, 150, 150), TapAction.menu);
  });

  test('kindle: top band is the menu, left column goes back', () {
    expect(tap(TapZoneLayout.kindle, 150, 10), TapAction.menu);
    expect(tap(TapZoneLayout.kindle, 10, 200), TapAction.previous);
    expect(tap(TapZoneLayout.kindle, 200, 200), TapAction.next);
  });

  test('disabled: every tap opens the menu', () {
    expect(tap(TapZoneLayout.disabled, 10, 10), TapAction.menu);
    expect(tap(TapZoneLayout.disabled, 290, 290), TapAction.menu);
  });

  test('a zero-size viewport is the menu, not a crash', () {
    expect(
      resolveTap(
        layout: TapZoneLayout.thirds,
        position: Offset.zero,
        size: Size.zero,
        mode: ReaderMode.pagedLtr,
      ),
      TapAction.menu,
    );
  });

  test('layout ids round-trip', () {
    for (final l in TapZoneLayout.values) {
      expect(TapZoneLayout.fromId(l.id), l);
      expect(l.label, isNotEmpty);
    }
    expect(TapZoneLayout.fromId('x'), isNull);
  });
}
