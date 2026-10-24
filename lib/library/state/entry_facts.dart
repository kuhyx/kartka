import 'dart:async';

import 'package:kartka/core/models/manga_key.dart';
import 'package:kartka/library/state/library_deps.dart';

/// Per-entry facts gathered from other parts' streams.
class EntryFacts {
  /// When a chapter was last read.
  DateTime? lastReadAt;

  /// Unread chapters, when known.
  int? unread;

  /// Has offline chapters.
  bool downloaded = false;

  /// Bound to a tracker.
  bool tracked = false;
}

/// Keeps one set of subscriptions per library entry: subscribes when a key
/// appears, cancels when it leaves, and calls [onChange] on every update.
class FactsTracker {
  /// Creates a tracker over [deps].
  new(this.deps, this.onChange);

  /// Stream sources.
  final LibraryDeps deps;

  /// Called after any fact changes.
  final void Function() onChange;

  final _facts = <MangaKey, EntryFacts>{};
  final _subs = <MangaKey, List<StreamSubscription<Object?>>>{};

  /// Facts for [key] (empty defaults for an untracked key).
  EntryFacts of(MangaKey key) => _facts[key] ?? EntryFacts();

  /// Makes the tracked keys exactly [keys].
  void track(Set<MangaKey> keys) {
    for (final gone in _facts.keys.where((k) => !keys.contains(k)).toList()) {
      _facts.remove(gone);
      for (final s in _subs.remove(gone)!) {
        unawaited(s.cancel());
      }
    }
    for (final key in keys.where((k) => !_facts.containsKey(k))) {
      final f = _facts[key] = EntryFacts();
      void set(void Function() apply) {
        apply();
        onChange();
      }

      _subs[key] = [
        deps.repos.progress
            .watch(key)
            .listen((p) => set(() => f.lastReadAt = p?.readAt)),
        deps.unread.watch(key).listen((n) => set(() => f.unread = n)),
        deps.downloaded
            .hasDownloads(key)
            .listen((d) => set(() => f.downloaded = d)),
        deps.tracked.isTracked(key).listen((t) => set(() => f.tracked = t)),
      ];
    }
  }

  /// Cancels every subscription.
  Future<void> dispose() async {
    final all = [for (final list in _subs.values) ...list];
    _subs.clear();
    _facts.clear();
    await Future.wait(all.map((s) => s.cancel()));
  }
}
