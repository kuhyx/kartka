import 'dart:async';

/// Per-row watchers of a `KvTable`: a write tells only the watchers of the
/// row it changed, so N rows watched one by one cost O(1) per write, not
/// O(N) (one shared stream filtered by every watcher made a sync pull
/// N-squared).
class RowWatchers<T> {
  final _byId = <String, Set<StreamController<T?>>>{};

  /// Callbacks run so far (the cost tests bound it).
  int callbacks = 0;

  /// A stream of row [id]: [read] once [ready] completes, then after every
  /// [changed] of that id. Cancelling before [ready] is safe.
  Stream<T?> watch(String id, Future<void> ready, T? Function() read) {
    late final StreamController<T?> out;
    var cancelled = false;
    out = StreamController<T?>(
      sync: true,
      onListen: () async {
        await ready;
        if (cancelled) return;
        // Registered in the same turn as the first value, so no change
        // falls between them.
        (_byId[id] ??= {}).add(out);
        callbacks++;
        out.add(read());
      },
      onCancel: () {
        cancelled = true;
        final watchers = _byId[id]?..remove(out);
        if (watchers != null && watchers.isEmpty) _byId.remove(id);
      },
    );
    return out.stream;
  }

  /// Tells the watchers of [id] its row is now [value].
  void changed(String id, T? value) {
    final watchers = _byId[id];
    if (watchers == null) return;
    for (final out in [...watchers]) {
      callbacks++;
      out.add(value);
    }
  }
}
