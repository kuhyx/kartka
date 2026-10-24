import 'dart:async';
import 'dart:developer';

import 'package:kartka/core/source/manga_source.dart';
import 'package:kartka/core/source/source_provider.dart';
import 'package:kartka/platform/image_headers.dart';
import 'package:kartka/sources/suwayomi/suwayomi_client.dart';
import 'package:kartka/sources/suwayomi/suwayomi_mappers.dart';
import 'package:kartka/sources/suwayomi/suwayomi_queries.dart';
import 'package:kartka/sources/suwayomi/suwayomi_settings.dart';
import 'package:kartka/sources/suwayomi/suwayomi_source.dart';

/// Every source installed on the configured Suwayomi-Server, one
/// [MangaSource] each (`suwayomi:<id>`), re-listed whenever the settings
/// change or an extension is installed, updated or removed.
///
/// A failed fetch is never cached: the next watcher fetches again, and the
/// provider retries by itself after [retryStart], doubling up to [retryCap],
/// until a fetch succeeds or it is disposed.
///
/// Also the [ImageHeaders] for the server: covers, pages and extension icons
/// under its URL get the basic-auth header, nothing else does.
class SuwayomiSourceProvider
    implements RefreshableSourceProvider, ImageHeaders {
  /// Creates the provider.
  new({required this.store, required this.client, this.titleOf});

  /// Persisted settings (watched for changes).
  final SuwayomiSettingsStore store;

  /// GraphQL client reading [store]'s current settings.
  final SuwayomiClient client;

  /// Library title lookup for manga the server has not seen.
  final TitleLookup? titleOf;

  /// First retry delay after a failed fetch.
  static const retryStart = Duration(seconds: 2);

  /// Longest retry delay.
  static const retryCap = Duration(seconds: 60);

  final _updates = StreamController<List<MangaSource>>.broadcast();
  final _byServerId = <String, SuwayomiSource>{};
  StreamSubscription<SuwayomiSettings>? _settingsChanges;
  List<MangaSource>? _last; // the last successful fetch only
  Timer? _retry;
  Duration _retryDelay = retryStart;
  bool _disposed = false;

  @override
  Stream<List<MangaSource>> watch() {
    _settingsChanges ??= store.changes.listen((_) {
      _byServerId.clear(); // another server means other ids
      _retry?.cancel(); // a new server gets the fast cadence
      _retry = null;
      _retryDelay = retryStart;
      unawaited(refresh());
    });
    StreamSubscription<List<MangaSource>>? forward;
    late final StreamController<List<MangaSource>> out;
    out = StreamController<List<MangaSource>>(
      onListen: () async {
        forward = _updates.stream.listen(out.add);
        out.add(_last ?? await _load());
      },
      onCancel: () => forward?.cancel(),
    );
    return out.stream;
  }

  /// Re-lists the server's sources and tells every watcher.
  @override
  Future<void> refresh() async {
    final sources = await _load();
    if (!_disposed) _updates.add(sources);
  }

  /// Stops watching the settings and retrying (tests; the app keeps it
  /// forever).
  Future<void> dispose() async {
    _disposed = true;
    _retry?.cancel();
    await _settingsChanges?.cancel();
    await _updates.close();
  }

  @override
  Map<String, String> forUrl(String url) {
    final settings = store.current;
    if (settings == null || !settings.owns(url)) return const {};
    return settings.authHeaders;
  }

  /// The server's sources; empty when unconfigured, unreachable or
  /// answering nonsense, so browsing keeps working offline with the other
  /// sources. Never throws: every watcher must get a list on subscribe, or
  /// the library's "unavailable source" badges stay hidden.
  Future<List<MangaSource>> _load() async {
    try {
      final sources = _last = await _fetch();
      _retry?.cancel();
      _retry = null;
      _retryDelay = retryStart;
      return sources;
    } on Object catch (e, st) {
      // Keystore read errors, HttpClient ArgumentErrors and shape errors
      // (TypeError) all mean "no Suwayomi sources right now", not "none".
      log(
        'Suwayomi sources fetch failed',
        name: 'kartka.suwayomi',
        error: e,
        stackTrace: st,
        level: 900,
      );
      _last = null;
      _scheduleRetry();
      return const [];
    }
  }

  void _scheduleRetry() {
    if (_disposed || (_retry?.isActive ?? false)) return;
    _retry = Timer(_retryDelay, () => unawaited(refresh()));
    final next = _retryDelay * 2;
    _retryDelay = next > retryCap ? retryCap : next;
  }

  Future<List<MangaSource>> _fetch() async {
    final settings = store.current ?? await store.load();
    if (!settings.isConfigured) return const [];
    final data = await client.run(SuwayomiQueries.sources);
    final nodes = (data['sources']! as Map<String, Object?>)['nodes']!;
    final sources = <MangaSource>[];
    for (final node in nodes as List<Object?>) {
      final info = SuwayomiSourceInfo.fromJson(node! as Map<String, Object?>);
      if (info.serverId == suwayomiLocalSourceId) continue;
      sources.add(
        _byServerId[info.serverId] ??= SuwayomiSource(
          info: info,
          client: client,
          settings: () => store.current ?? settings,
          titleOf: titleOf,
        ),
      );
    }
    return List.unmodifiable(sources);
  }
}
