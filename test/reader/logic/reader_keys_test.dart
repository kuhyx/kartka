import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/reader/logic/reader_keys.dart';
import 'package:kartka/reader/logic/reader_mode.dart';

void main() {
  ReaderIntent? key(
    LogicalKeyboardKey k, {
    ReaderMode mode = ReaderMode.pagedLtr,
    bool shift = false,
  }) => intentForKey(k, mode: mode, shift: shift);

  test('LTR arrows follow the screen', () {
    expect(key(LogicalKeyboardKey.arrowRight), ReaderIntent.next);
    expect(key(LogicalKeyboardKey.arrowLeft), ReaderIntent.previous);
  });

  test('RTL arrows are mirrored', () {
    const m = ReaderMode.pagedRtl;
    expect(key(LogicalKeyboardKey.arrowLeft, mode: m), ReaderIntent.next);
    expect(key(LogicalKeyboardKey.arrowRight, mode: m), ReaderIntent.previous);
  });

  test('up/down, space and page keys', () {
    expect(key(LogicalKeyboardKey.arrowDown), ReaderIntent.next);
    expect(key(LogicalKeyboardKey.arrowUp), ReaderIntent.previous);
    expect(key(LogicalKeyboardKey.space), ReaderIntent.next);
    expect(key(LogicalKeyboardKey.space, shift: true), ReaderIntent.previous);
    expect(key(LogicalKeyboardKey.pageDown), ReaderIntent.next);
    expect(key(LogicalKeyboardKey.pageUp), ReaderIntent.previous);
  });

  test('f toggles fullscreen, Escape goes back, others are ignored', () {
    expect(key(LogicalKeyboardKey.keyF), ReaderIntent.toggleFullscreen);
    expect(key(LogicalKeyboardKey.escape), ReaderIntent.back);
    expect(key(LogicalKeyboardKey.keyQ), isNull);
  });
}
