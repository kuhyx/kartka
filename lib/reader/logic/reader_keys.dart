import 'package:flutter/services.dart';
import 'package:kartka/reader/logic/reader_mode.dart';

/// A reader command, independent of the input that produced it.
enum ReaderIntent {
  /// Forward one page (or one screen in webtoon mode).
  next,

  /// Back one page (or one screen in webtoon mode).
  previous,

  /// Enter or leave fullscreen.
  toggleFullscreen,

  /// Leave the reader.
  back,
}

/// Maps a desktop key press to a [ReaderIntent], or null when unbound.
///
/// Horizontal arrows follow the screen, so right-to-left mode mirrors them;
/// vertical arrows, Space and PgUp/PgDn always mean forward/back.
ReaderIntent? intentForKey(
  LogicalKeyboardKey key, {
  required ReaderMode mode,
  bool shift = false,
}) {
  final rtl = mode.reversed;
  if (key == LogicalKeyboardKey.arrowRight) {
    return rtl ? ReaderIntent.previous : ReaderIntent.next;
  }
  if (key == LogicalKeyboardKey.arrowLeft) {
    return rtl ? ReaderIntent.next : ReaderIntent.previous;
  }
  if (key == LogicalKeyboardKey.space) {
    return shift ? ReaderIntent.previous : ReaderIntent.next;
  }
  if (key == LogicalKeyboardKey.arrowDown ||
      key == LogicalKeyboardKey.pageDown) {
    return ReaderIntent.next;
  }
  if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.pageUp) {
    return ReaderIntent.previous;
  }
  if (key == LogicalKeyboardKey.keyF) return ReaderIntent.toggleFullscreen;
  if (key == LogicalKeyboardKey.escape) return ReaderIntent.back;
  return null;
}
