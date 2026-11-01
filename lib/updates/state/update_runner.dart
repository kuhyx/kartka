import 'package:flutter/foundation.dart';
import 'package:kartka/browse/state/refresh_outcome.dart';
import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/source/unknown_source_error.dart';
import 'package:kartka/core/updates/chapter_update_checker.dart';
import 'package:kartka/library/data/lww.dart';
import 'package:kartka/library/ports.dart';
import 'package:kartka/updates/state/network_errors.dart';
import 'package:kartka/updates/state/update_scheduler.dart';

/// Waits [duration] (the retry backoff; tests pass a no-op).
typedef Delay = Future<void> Function(Duration duration);

Future<void> _wait(Duration d) => Future<void>.delayed(d);

/// The error of a check skipped because its server was found unreachable.
final class _NotChecked {
  const new();
}

/// The error of a check skipped because its source is not installed.
final class _Unavailable {
  const new();
}

/// The one shared "update all" run ([LibraryUpdater]).
///
/// Checks every library manga through [check] (4 at a time, 1 per source,
/// 2 per server), publishes [progress] as checks finish, and logs each
/// failure to [diagnostics] as `updates.check` when it happens, with the
/// source id only: no manga url, URLs stripped from the message.
///
/// A network failure (`isTransientNetworkError`) is retried [retries]
/// times, waiting [backoff], then twice that. When a server still cannot be
/// reached (`isOfflineError`), its remaining manga are not checked: one
/// `updates.offline` entry per server, counted as `notChecked`, not
/// `failed`. A source nothing is registered for (`UnknownSourceError`) is
/// the same, once per source: one `updates.unavailable` entry, its manga
/// counted as `unavailable`. New chapters reach the updates feed
/// through `ChapterAdditionSink`, not from here, so a run writes each
/// chapter once.
class UpdateRunner extends ChangeNotifier implements LibraryUpdater {
  /// Creates the runner.
  new({
    required this.libraryKeys,
    required this.check,
    this.diagnostics,
    this.clock = utcNow,
    this.retries = 2,
    this.backoff = const Duration(seconds: 1),
    this.delay = _wait,
  });

  /// Keys of every manga in the library, read when a run starts.
  final Future<List<MangaKey>> Function() libraryKeys;

  /// Checks one manga.
  final CheckManga check;

  /// Where failures are logged; `null` logs nothing.
  final DiagnosticsLog? diagnostics;

  /// Clock for diagnostics entries.
  final DateTime Function() clock;

  /// Retries of a check that failed on the network.
  final int retries;

  /// Wait before the first retry; doubled for each next one.
  final Duration backoff;

  /// How the backoff is waited.
  final Delay delay;

  Future<UpdateSummary>? _run;
  UpdateProgress? _progress;

  @override
  UpdateProgress? get progress => _progress;

  @override
  Future<UpdateSummary> updateAll() => _run ??= _runOnce();

  Future<UpdateSummary> _runOnce() async {
    final run = _Run();
    try {
      final keys = await libraryKeys();
      _publish(keys.isEmpty ? null : UpdateProgress(0, keys.length));
      final results = await checkAll(
        keys,
        (key) => _guarded(key, run),
        onResult: (result, done) {
          _publish(UpdateProgress(done, keys.length));
          if (result is UpdateFailed && !_isSkip(result.error)) {
            run.logs.add(_log('updates.check', result.error, result, null));
          }
        },
      );
      return await _summarise(results, run);
    } finally {
      _run = null;
      _publish(null);
    }
  }

  /// [check] with retries; a key of a server already found down is not
  /// checked, and one that finds it down marks it.
  Future<UpdateResult> _guarded(MangaKey key, _Run run) async {
    final host = updateHostOf(splitMangaKey(key).$1);
    final sourceId = splitMangaKey(key).$1;
    for (var attempt = 0; ; attempt++) {
      if (run.down.containsKey(host)) {
        return UpdateFailed(key, const _NotChecked());
      }
      if (run.missing.contains(sourceId)) {
        return UpdateFailed(key, const _Unavailable());
      }
      final result = await check(key);
      if (result is UpdateFailed && result.error is UnknownSourceError) {
        if (run.missing.add(sourceId)) {
          run.logs.add(_log('updates.unavailable', result.error, result, null));
        }
        return UpdateFailed(key, const _Unavailable());
      }
      if (result is! UpdateFailed || !isTransientNetworkError(result.error)) {
        return result;
      }
      if (attempt >= retries) {
        if (!isOfflineError(result.error)) return result;
        run.down[host] ??= result.error;
        return UpdateFailed(key, const _NotChecked());
      }
      await delay(backoff * (1 << attempt));
    }
  }

  Future<void> _log(
    String kind,
    Object error,
    UpdateResult? result,
    String? sourceId,
  ) async => await diagnostics?.append(
    DiagnosticEntry.failure(
      at: clock(),
      kind: kind,
      error: stripUrls('$error'),
      stack: result is UpdateFailed ? result.stack : null,
      sourceId: sourceId ?? splitMangaKey(result!.key).$1,
    ),
  );

  static bool _isSkip(Object error) =>
      error is _NotChecked || error is _Unavailable;

  void _publish(UpdateProgress? p) {
    if (p == _progress) return;
    _progress = p;
    notifyListeners();
  }

  Future<UpdateSummary> _summarise(List<UpdateResult> results, _Run run) async {
    var chapters = 0;
    var manga = 0;
    var failed = 0;
    var unavailable = 0;
    final skipped = <String, int>{};
    for (final r in results) {
      switch (r) {
        case UpdateFound(:final added):
          chapters += added.length;
          if (added.isNotEmpty) manga++;
        case UpdateFailed(error: _NotChecked()):
          final host = updateHostOf(splitMangaKey(r.key).$1);
          skipped[host] = (skipped[host] ?? 0) + 1;
        case UpdateFailed(error: _Unavailable()):
          unavailable++;
        case UpdateFailed():
          failed++;
      }
    }
    for (final MapEntry(key: host, value: error) in run.down.entries) {
      final n = skipped[host] ?? 0;
      run.logs.add(
        _log('updates.offline', '$error · $n not checked', null, host),
      );
    }
    await Future.wait(run.logs);
    return UpdateSummary(
      newChapters: chapters,
      manga: manga,
      failed: failed,
      notChecked: skipped.values.fold(0, (a, b) => a + b),
      unavailable: unavailable,
    );
  }
}

/// What one run shares between its checks.
class _Run {
  /// Servers found unreachable, with the first error that showed it.
  final down = <String, Object>{};

  /// Source ids found not installed (each logged once).
  final missing = <String>{};

  /// Diagnostics writes in flight, awaited before the summary.
  final logs = <Future<void>>[];
}
