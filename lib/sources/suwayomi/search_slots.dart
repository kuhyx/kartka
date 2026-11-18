import 'dart:async';
import 'dart:collection';

/// At most [size] jobs at once; the rest wait in order.
///
/// Caps the title searches that find a manga the server has not seen by
/// url (`SuwayomiSource`): a library of such manga sent about ten at once,
/// 3-17 s each, which on the web filled the browser's six connections to
/// the wrapper so the reader's own requests queued behind them (reader.open
/// 5-78 s, 971debc8).
class SearchSlots {
  /// Slots for [size] jobs at once.
  new(this.size);

  /// Jobs that may run at once.
  final int size;

  var _running = 0;
  final _waiting = Queue<Completer<void>>();

  /// Runs [job] once a slot is free.
  Future<T> run<T>(Future<T> Function() job) async {
    if (_running >= size) {
      final turn = Completer<void>();
      _waiting.add(turn);
      await turn.future;
    } else {
      _running++;
    }
    try {
      return await job();
    } finally {
      // The slot passes straight to the next job, or frees.
      if (_waiting.isNotEmpty) {
        _waiting.removeFirst().complete();
      } else {
        _running--;
      }
    }
  }
}
