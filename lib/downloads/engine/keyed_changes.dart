import 'dart:async';

import 'package:kartka/core/models/models.dart';

/// Change notifications routed by manga: a watcher of one manga's badge or
/// chapter state is told only about that manga, so a progress tick of one
/// download does not make every library row re-read its state.
class KeyedChanges {
  final _all = StreamController<void>.broadcast(sync: true);
  final _byKey = <MangaKey, Set<MultiStreamController<void>>>{};

  /// Every change, whichever manga it is for (the Downloads screen).
  Stream<void> get all => _all.stream;

  /// Changes of [key], and the ones that concern every manga.
  Stream<void> of(MangaKey key) => Stream<void>.multi((out) {
    // Registered when listened to, so a stream nobody listens to yet holds
    // nothing that another watcher's cancel could tear down.
    (_byKey[key] ??= {}).add(out);
    out.onCancel = () {
      final sinks = _byKey[key]?..remove(out);
      if (sinks != null && sinks.isEmpty) _byKey.remove(key);
    };
  }, isBroadcast: true);

  /// Something about [key] changed.
  void notify(MangaKey key) {
    for (final out in [...?_byKey[key]]) {
      out.addSync(null);
    }
    _all.add(null);
  }

  /// Something that touches every manga changed (pause, resume).
  void notifyAll() {
    for (final out in [for (final s in _byKey.values) ...s]) {
      out.addSync(null);
    }
    _all.add(null);
  }
}
