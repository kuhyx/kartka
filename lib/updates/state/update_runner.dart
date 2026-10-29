import 'package:flutter/foundation.dart';
import 'package:kartka/browse/state/refresh_outcome.dart';
import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/updates/chapter_update_checker.dart';
import 'package:kartka/library/data/lww.dart';
import 'package:kartka/library/ports.dart';
import 'package:kartka/updates/state/update_scheduler.dart';

/// The one shared "update all" run ([LibraryUpdater]).
///
/// Checks every library manga through [check] (4 at a time, 1 per source),
/// publishes [progress] as checks finish, and logs each failure to
/// [diagnostics] as `updates.check` with the source id only: no manga url,
/// URLs stripped from the message. New chapters reach the updates feed
/// through `ChapterAdditionSink`, not from here, so a run writes each
/// chapter once.
class UpdateRunner extends ChangeNotifier implements LibraryUpdater {
  /// Creates the runner.
  new({
    required this.libraryKeys,
    required this.check,
    this.diagnostics,
    this.clock = utcNow,
  });

  /// Keys of every manga in the library, read when a run starts.
  final Future<List<MangaKey>> Function() libraryKeys;

  /// Checks one manga.
  final CheckManga check;

  /// Where failures are logged; `null` logs nothing.
  final DiagnosticsLog? diagnostics;

  /// Clock for diagnostics entries.
  final DateTime Function() clock;

  Future<UpdateSummary>? _run;
  UpdateProgress? _progress;

  @override
  UpdateProgress? get progress => _progress;

  @override
  Future<UpdateSummary> updateAll() => _run ??= _runOnce();

  Future<UpdateSummary> _runOnce() async {
    try {
      final keys = await libraryKeys();
      _publish(keys.isEmpty ? null : UpdateProgress(0, keys.length));
      final results = await checkAll(
        keys,
        check,
        onResult: (_, done) => _publish(UpdateProgress(done, keys.length)),
      );
      return await _summarise(results);
    } finally {
      _run = null;
      _publish(null);
    }
  }

  void _publish(UpdateProgress? p) {
    if (p == _progress) return;
    _progress = p;
    notifyListeners();
  }

  Future<UpdateSummary> _summarise(List<UpdateResult> results) async {
    var chapters = 0;
    var manga = 0;
    var failed = 0;
    for (final r in results) {
      switch (r) {
        case UpdateFound(:final added):
          chapters += added.length;
          if (added.isNotEmpty) manga++;
        case UpdateFailed(:final error, :final stack):
          failed++;
          await diagnostics?.append(
            DiagnosticEntry.failure(
              at: clock(),
              kind: 'updates.check',
              error: stripUrls('$error'),
              stack: stack,
              sourceId: splitMangaKey(r.key).$1,
            ),
          );
      }
    }
    return UpdateSummary(newChapters: chapters, manga: manga, failed: failed);
  }
}
