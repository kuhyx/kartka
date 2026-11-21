import 'dart:async';
import 'dart:convert';

import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/redact.dart';
import 'package:kartka/core/source/manga_gone_error.dart';
import 'package:kartka/core/source/unknown_source_error.dart';
import 'package:kartka/core/updates/chapter_update_checker.dart';
import 'package:kartka/core/updates/check_all.dart';
import 'package:kartka/platform/key_value_store.dart';

/// At most this many entries are fetched per [ChapterBackfill.fill].
const int backfillLimit = 20;

/// Diagnostics kind of a failed backfill fetch (device only).
const String backfillKind = 'library.backfill';

/// Local key of the entries whose fetch failed (`{key: triedAt}`).
const String backfillTriedKey = 'library.backfill.tried';

/// Fetches the chapter list of library entries that have none stored yet,
/// so auto-shelving and duplicate merging can judge them (audit 53c9b0fa,
/// gaps 5a and 6: such entries were skipped for good).
///
/// Each [fill] fetches the [backfillLimit] oldest-added entries through the
/// [ChapterUpdateChecker] (which stores the list), 2 at a time and 1 per
/// source. An entry whose fetch failed is remembered and goes after every
/// untried one, so one dead source never blocks the rest; it leaves the
/// record once a fetch stores its list. A gone manga or a missing source is
/// skipped silently (the library shows those already); any other failure
/// is logged on the device as [backfillKind] without URLs.
class ChapterBackfill {
  /// A backfill over [checker] (null: nothing to fetch with yet).
  new({
    required this.checker,
    required this.local,
    required this.log,
    required this.clock,
  });

  /// The checker, read at each [fill] (registered after startup).
  final ChapterUpdateChecker? Function() checker;

  /// Device-local store of the tried record.
  final KeyValueStore local;

  /// The diagnostics log failures go to.
  final DiagnosticsLog log;

  /// The current time.
  final DateTime Function() clock;

  Future<Set<MangaKey>>? _running;

  /// Fetches up to [backfillLimit] of [missing] (entries with no stored
  /// chapter list) and returns the keys whose list is now stored. A call
  /// while one runs joins it.
  Future<Set<MangaKey>> fill(List<LibraryEntry> missing) =>
      _running ??= _fill(missing).whenComplete(() => _running = null);

  Future<Set<MangaKey>> _fill(List<LibraryEntry> missing) async {
    final using = checker();
    if (using == null || missing.isEmpty) return const {};
    final tried = await _tried();
    final order = [...missing]
      ..sort((a, b) {
        final byTried = (tried.containsKey(a.key) ? 1 : 0).compareTo(
          tried.containsKey(b.key) ? 1 : 0,
        );
        return byTried != 0 ? byTried : a.addedAt.compareTo(b.addedAt);
      });
    final batch = [for (final e in order.take(backfillLimit)) e.key];
    final results = await checkAll(batch, using.check, maxTotal: 2);
    final stored = <MangaKey>{};
    for (final result in results) {
      switch (result) {
        case UpdateFound(:final key):
          stored.add(key);
          tried.remove(key);
        case UpdateFailed(:final key, :final error):
          tried[key] = clock().toUtc().toIso8601String();
          await _logFailure(key, error);
      }
    }
    await local.set(backfillTriedKey, jsonEncode(tried));
    return stored;
  }

  Future<void> _logFailure(MangaKey key, Object error) async {
    if (error is MangaGoneError || error is UnknownSourceError) return;
    await log.append(
      DiagnosticEntry.failure(
        at: clock().toUtc(),
        kind: backfillKind,
        error: stripUrls('$error'),
        sourceId: splitMangaKey(key).$1,
      ),
    );
  }

  Future<Map<String, String>> _tried() async {
    final raw = await local.get(backfillTriedKey);
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as Map<String, Object?>).cast<String, String>();
    } on FormatException {
      return {};
    }
  }
}

/// The facts [of] knows for each of [entries], after [backfill] fetched
/// the chapter lists of those it did not know (null: no backfill).
Future<Map<MangaKey, F>> knownFacts<F extends Object>(
  List<LibraryEntry> entries,
  Future<F?> Function(MangaKey key) of,
  ChapterBackfill? backfill,
) async {
  final known = <MangaKey, F>{};
  final missing = <LibraryEntry>[];
  for (final e in entries) {
    final f = await of(e.key);
    f == null ? missing.add(e) : known[e.key] = f;
  }
  final stored = await backfill?.fill(missing) ?? const {};
  for (final key in stored) {
    final f = await of(key);
    if (f != null) known[key] = f;
  }
  return known;
}
