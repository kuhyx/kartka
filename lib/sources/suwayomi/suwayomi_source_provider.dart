import 'dart:async';

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
/// Also the [ImageHeaders] for the server: covers, pages and extension icons
/// under its URL get the basic-auth header, nothing else does.
class SuwayomiSourceProvider implements SourceProvider, ImageHeaders {
  /// Creates the provider.
  new({required this.store, required this.client, this.titleOf});

  /// Persisted settings (watched for changes).
  final SuwayomiSettingsStore store;

  /// GraphQL client reading [store]'s current settings.
  final SuwayomiClient client;

  /// Library title lookup for manga the server has not seen.
  final TitleLookup? titleOf;

  final _updates = StreamController<List<MangaSource>>.broadcast();
  final _byServerId = <String, SuwayomiSource>{};
  StreamSubscription<SuwayomiSettings>? _settingsChanges;
  List<MangaSource>? _last;

  @override
  Stream<List<MangaSource>> watch() {
    _settingsChanges ??= store.changes.listen((_) {
      _byServerId.clear(); // another server means other ids
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
  Future<void> refresh() async => _updates.add(await _load());

  /// Stops watching the settings (tests; the app keeps it forever).
  Future<void> dispose() async {
    await _settingsChanges?.cancel();
    await _updates.close();
  }

  @override
  Map<String, String> forUrl(String url) {
    final settings = store.current;
    if (settings == null || !settings.owns(url)) return const {};
    return settings.authHeaders;
  }

  /// The server's sources; empty when unconfigured or unreachable, so
  /// browsing keeps working offline with the other sources.
  Future<List<MangaSource>> _load() async {
    final settings = store.current ?? await store.load();
    if (!settings.isConfigured) return _last = const [];
    final Map<String, Object?> data;
    try {
      data = await client.run(SuwayomiQueries.sources);
    } on Exception {
      return _last = const [];
    }
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
    return _last = List.unmodifiable(sources);
  }
}
