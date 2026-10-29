import 'dart:async';

import 'package:kartka/core/models/models.dart';

/// The keys of every library manga, kept current from one long-lived
/// subscription (for the app's lifetime), so a feed write or an update-all
/// run asks "in the library?" without re-reading the whole library, and
/// without `watch().first`, whose cancel completes in the root zone.
class LibraryKeys {
  /// Follows the stream `watch` returns (normally
  /// `LibraryRepository.watch`), subscribed on first use, never cancelled.
  new(this._watch);

  final Stream<List<LibraryEntry>> Function() _watch;
  bool _following = false;
  final _first = Completer<void>();
  List<MangaKey> _keys = const [];

  /// The current keys, in library order (waits for the first snapshot).
  Future<List<MangaKey>> current() async {
    if (!_following) {
      _following = true;
      _watch().listen((entries) {
        _keys = List.unmodifiable([for (final e in entries) e.key]);
        if (!_first.isCompleted) _first.complete();
      });
    }
    await _first.future;
    return _keys;
  }

  /// Whether [key] is in the library now.
  Future<bool> contains(MangaKey key) async => (await current()).contains(key);
}
