import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/platform/fullscreen.dart';

void main() {
  test('outside a browser fullscreen is a no-op that reports false', () async {
    await setBrowserFullscreen(on: true);
    expect(browserFullscreen, isFalse);
    await setBrowserFullscreen(on: false);
    expect(browserFullscreen, isFalse);
  });
}
