import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/source/manga_source.dart';
import 'package:kartka/plugins/runtime/host_api.dart';
import 'package:kartka/plugins/runtime/plugin_mapping.dart';
import 'package:kartka/plugins/runtime/plugin_session.dart';

/// An installed plugin as a [MangaSource] with id `plugin:<id>`.
class PluginSource implements MangaSource {
  /// Wraps [session].
  new(this.session) : _map = PluginMapper(session.manifest.id);

  /// The running plugin.
  final PluginSession session;
  final PluginMapper _map;

  @override
  SourceRef get ref => SourceRef(
    id: session.manifest.sourceId,
    name: session.manifest.name,
    lang: session.manifest.lang,
    origin: SourceOrigin.plugin,
  );

  @override
  Future<SearchPage> popular(int page) async => _map.page(
    PluginMethod.popular,
    await _call(PluginMethod.popular, [page]),
  );

  @override
  Future<SearchPage> latest(int page) async =>
      _map.page(PluginMethod.latest, await _call(PluginMethod.latest, [page]));

  @override
  Future<SearchPage> search(String query, int page) async => _map.page(
    PluginMethod.search,
    await _call(PluginMethod.search, [query, page]),
  );

  @override
  Future<MangaDetails> details(String mangaUrl) async =>
      _map.details(await _call(PluginMethod.details, [mangaUrl]));

  @override
  Future<List<ChapterInfo>> chapters(String mangaUrl) async =>
      _map.chapters(await _call(PluginMethod.chapters, [mangaUrl]));

  @override
  Future<List<PageRef>> pages(String chapterUrl) async =>
      _map.pages(await _call(PluginMethod.pages, [chapterUrl]));

  Future<Object?> _call(PluginMethod m, List<Object?> args) =>
      session.call(m, args);
}
