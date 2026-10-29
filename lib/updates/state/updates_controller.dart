import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kartka/browse/state/read_state.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/updates/state/update_rows.dart';
import 'package:kartka/updates/state/updates_deps.dart';

/// State of the Updates tab: the feed joined with the library and each
/// shown manga's read marks, flattened to [rows] once per change (never in
/// build).
class UpdatesController extends ChangeNotifier {
  /// Creates the controller over [deps]; call [start].
  new(this.deps);

  /// What it reads.
  final UpdatesDeps deps;

  StreamSubscription<List<LibraryEntry>>? _librarySub;
  final Map<MangaKey, StreamSubscription<ReadMarks>> _markSubs = {};
  final Map<MangaKey, ReadMarks> _marks = {};
  Map<MangaKey, LibraryEntry>? _library;

  /// The rows to show.
  List<UpdateRow> rows = const [];

  /// Whether both the feed and the library have been read.
  bool get loaded => deps.feed.loaded && _library != null;

  /// Starts listening.
  void start() {
    deps.feed.addListener(_rebuild);
    _librarySub = deps.library.watch().listen((entries) {
      _library = {for (final e in entries) e.key: e};
      _rebuild();
    });
    unawaited(deps.feed.load());
  }

  void _rebuild() {
    final library = _library ?? const {};
    final shown = {
      for (final e in deps.feed.events)
        if (library.containsKey(e.key)) e.key,
    };
    for (final key in [..._markSubs.keys]) {
      if (shown.contains(key)) continue;
      unawaited(_markSubs.remove(key)!.cancel());
      _marks.remove(key);
    }
    for (final key in shown) {
      _markSubs[key] ??= watchReadMarks(deps.progress, key).listen((m) {
        _marks[key] = m;
        _regroup();
      });
    }
    _regroup();
  }

  // Only regroups: a read-marks event never touches the subscriptions.
  void _regroup() {
    rows = groupUpdates(
      deps.feed.events,
      library: _library ?? const {},
      marks: _marks,
      now: deps.clock(),
    );
    notifyListeners();
  }

  @override
  void dispose() {
    deps.feed.removeListener(_rebuild);
    unawaited(_librarySub?.cancel());
    for (final s in _markSubs.values) {
      unawaited(s.cancel());
    }
    super.dispose();
  }
}
