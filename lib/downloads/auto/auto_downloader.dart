import 'dart:async';
import 'dart:convert';

import 'package:kartka/core/models/models.dart';
import 'package:kartka/downloads/engine/download_engine.dart';
import 'package:kartka/downloads/keys.dart';
import 'package:kartka/platform/key_value_store.dart';

/// Builds a periodic timer; injectable so tests need not wait hours.
typedef PeriodicTimer = Timer Function(
  Duration every,
  void Function(Timer) tick,
);

/// Queues chapters that appeared since the last check, for library manga,
/// when the "auto-download new chapters" setting is on.
///
/// Runs only while the app is open (start + every [schedule] period); there
/// is no background worker in v1. The first time a manga is seen its current
/// chapters become the baseline, so enabling the setting never downloads a
/// whole back catalogue.
class AutoDownloader {
  /// Creates the checker.
  new({
    required this.kv,
    required this.library,
    required this.findSource,
    required this.enqueue,
  });

  /// Setting and known-chapter storage.
  final KeyValueStore kv;

  /// Library entries (the library accessor's `library.watch()`).
  final Stream<List<LibraryEntry>> Function() library;

  /// Resolves an entry's source.
  final SourceLookup findSource;

  /// Queues one chapter (the download service's `enqueue`).
  final Future<void> Function(MangaKey key, ChapterInfo chapter) enqueue;

  Timer? _timer;

  /// Whether new chapters are downloaded automatically.
  Future<bool> enabled() async => await kv.get(autoDownloadKvKey) == 'true';

  /// Turns the setting on or off.
  Future<void> setEnabled({required bool enabled}) =>
      kv.set(autoDownloadKvKey, '$enabled');

  /// Checks every library manga once; returns how many chapters were queued.
  Future<int> check() async {
    if (!await enabled()) return 0;
    var queued = 0;
    for (final entry in await library().first) {
      if (entry.removed) continue;
      final source = await findSource(entry.sourceId);
      if (source == null) continue;
      final List<ChapterInfo> chapters;
      try {
        chapters = await source.chapters(entry.mangaUrl);
      } on Object {
        continue; // a source that is down is retried at the next check
      }
      queued += await _diff(entry.key, chapters);
    }
    return queued;
  }

  Future<int> _diff(MangaKey key, List<ChapterInfo> chapters) async {
    final kvKey = '$knownChaptersKvPrefix${mangaKeyHash(key)}';
    final raw = await kv.get(kvKey);
    final known = raw == null
        ? null
        : (jsonDecode(raw) as List<Object?>).cast<String>().toSet();
    final fresh = [
      if (known != null)
        for (final c in chapters)
          if (!known.contains(c.url)) c,
    ];
    for (final c in fresh) {
      await enqueue(key, c);
    }
    final all = {...?known, for (final c in chapters) c.url};
    await kv.set(kvKey, jsonEncode(all.toList()));
    return fresh.length;
  }

  /// Checks now and then every [every] until [dispose].
  void schedule({
    Duration every = const Duration(hours: 6),
    PeriodicTimer periodic = Timer.periodic,
  }) {
    unawaited(check());
    _timer = periodic(every, (_) => unawaited(check()));
  }

  /// Stops the schedule.
  void dispose() => _timer?.cancel();
}
