import 'package:kartka/plugins/runtime/engine.dart';
import 'package:kartka/plugins/runtime/engine_quickjs.dart';
import 'package:kartka/plugins/runtime/host_api.dart';

import 'support.dart';

/// Results of driving one recorded extension through all six entry points
/// exactly as the recorder did (`record_test.dart`).
typedef Replay = ({
  Map<String, Object?> popular,
  Map<String, Object?> latest,
  Map<String, Object?> search,
  Map<String, Object?> details,
  List<Object?> chapters,
  List<Object?> pages,
  ReplayServices services,
});

/// Replays `http/<name>.json` offline.
Future<Replay> replay(
  String name, {
  String? pagesUrl,
  JsEngineFactory engine = QuickJsEngine.new,
}) async {
  final rec = recording(name);
  final services = ReplayServices(rec.exchanges);
  final j = fixtureJson('http/$name.json')! as Map<String, Object?>;
  final session = sessionFor(
    rec.entry,
    rec.exchanges.first.body,
    services,
    engine: engine,
  );
  try {
    Future<T> call<T>(PluginMethod m, List<Object?> args) async =>
        (await session.call(m, args)) as T;
    final popular = await call<Map<String, Object?>>(PluginMethod.popular, [1]);
    final latest = await call<Map<String, Object?>>(PluginMethod.latest, [1]);
    final search = await call<Map<String, Object?>>(PluginMethod.search, [
      j['query'],
      1,
    ]);
    final url = j['firstItem'];
    final details = await call<Map<String, Object?>>(PluginMethod.details, [
      url,
    ]);
    final chapters = await call<List<Object?>>(PluginMethod.chapters, [url]);
    final chapterUrl = chapters.isEmpty
        ? pagesUrl
        : (chapters.last! as Map)['url'];
    final pages = await call<List<Object?>>(PluginMethod.pages, [chapterUrl]);
    return (
      popular: popular,
      latest: latest,
      search: search,
      details: details,
      chapters: chapters,
      pages: pages,
      services: services,
    );
  } finally {
    await session.dispose();
  }
}
