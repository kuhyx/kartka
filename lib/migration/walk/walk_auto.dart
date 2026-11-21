import 'package:flutter/foundation.dart';
import 'package:kartka/migration/same_manga.dart';
import 'package:kartka/migration/walk/walk_controller.dart';

/// The automatic pass over a walk: from the current entry on, one by one,
/// every entry whose best alternative is a strong match ([strongMatch],
/// the matcher's own "strong" bar, final scores only) migrates the way a
/// tap on its card does. It stops on the first weaker entry (left for
/// manual review), a failed backup or migration, the end, or [stop].
class WalkAutoPass extends ChangeNotifier {
  /// A pass over [_walk].
  new(this._walk);

  final MigrationWalkController _walk;

  /// Whether the pass is going.
  bool running = false;

  /// Entries this pass migrated.
  int moved = 0;

  var _stop = false;
  var _disposed = false;

  /// Runs the pass; a second call while it runs does nothing.
  Future<void> run() async {
    if (running || _disposed) return;
    running = true;
    _stop = false;
    moved = 0;
    _notify();
    try {
      while (!_stop && !_disposed) {
        final item = _walk.current;
        if (item == null) break;
        if (item.migratedTo != null) {
          _walk.skip();
          continue;
        }
        final best = await _bestOf(item);
        if (_stop || _disposed || !identical(_walk.current, item)) break;
        if (best == null || best.score < strongMatch) break;
        await _walk.migrateTo(best);
        if (item.migratedTo == null) break;
        moved++;
        _notify();
      }
    } finally {
      running = false;
      _notify();
    }
  }

  /// Ends the pass once the migration in flight (if any) is written.
  void stop() => _stop = true;

  /// The best alternative of [item] once its search (or a manual search
  /// that replaced it) has its final scores; null when there is none.
  static Future<MigrationCandidate?> _bestOf(WalkItem item) async {
    Future<void>? seen;
    while (!identical(seen, item.pending)) {
      seen = item.pending;
      if (seen == null) return null;
      await seen;
    }
    return item.found?.best.firstOrNull;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stop = true;
    super.dispose();
  }
}
