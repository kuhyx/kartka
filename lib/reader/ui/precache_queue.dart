import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:kartka/reader/ui/page_precache.dart';

/// Decodes the pages around the reader into the image cache, gently.
///
/// Decoding a page (and uploading it to the GPU) costs tens of milliseconds,
/// so it must not land in a swipe: [schedule] waits until the reader has
/// stopped moving for [settle], then decodes the pages one at a time, in the
/// order given. A newer [schedule] (the user swiped on or jumped) drops
/// whatever the older one had not started yet.
class PrecacheQueue {
  /// A queue that decodes through [decode] after [settle] of quiet.
  new({required this.decode, this.settle = const Duration(milliseconds: 150)});

  /// Decodes one provider into the image cache; errors are ignored.
  final Future<void> Function(ImageProvider provider) decode;

  /// How long the reader must be still before decoding starts.
  final Duration settle;

  /// The most pages remembered as decoded (older ones may have left the
  /// image cache anyway, and decoding twice is only a cache hit).
  static const int _remembered = 16;

  Timer? _timer;
  int _generation = 0;
  bool _running = false;

  // Page bytes (by identity) to the width they were decoded at.
  final Map<Uint8List, int> _done = Map.identity();

  /// Whether nothing is waiting or decoding.
  bool get isIdle => _timer == null && !_running;

  /// Replaces the plan with [pages] (bytes still downloading are awaited in
  /// turn), to be decoded [width] pixels wide once the reader is still.
  void schedule(List<Future<Uint8List>> pages, int width) {
    cancel();
    // A page may fail to load while the queue is still waiting to start;
    // the failure is handled here, by skipping it.
    for (final page in pages) {
      page.ignore();
    }
    final generation = _generation;
    _timer = Timer(settle, () {
      _timer = null;
      unawaited(_run(generation, pages, width));
    });
  }

  /// Drops everything not yet started.
  void cancel() {
    _generation++;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _run(
    int generation,
    List<Future<Uint8List>> pages,
    int w,
  ) async {
    _running = true;
    try {
      for (final page in pages) {
        final Uint8List bytes;
        try {
          bytes = await page;
        } on Object {
          continue;
        }
        if (generation != _generation) return;
        if (_done[bytes] == w) continue;
        _remember(bytes, w);
        try {
          await decode(readerPageProvider(bytes, w));
        } on Object {
          // The page shows its own retry when it cannot decode.
        }
        if (generation != _generation) return;
      }
    } finally {
      _running = false;
    }
  }

  void _remember(Uint8List bytes, int width) {
    _done.remove(bytes);
    _done[bytes] = width;
    if (_done.length > _remembered) _done.remove(_done.keys.first);
  }
}
