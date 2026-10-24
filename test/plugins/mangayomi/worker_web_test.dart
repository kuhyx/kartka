@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/platform/web/plugin_worker_engine.dart';
import 'package:kartka/plugins/mangayomi/mangayomi_converter.dart';
import 'package:kartka/plugins/mangayomi/mangayomi_entry.dart';
import 'package:kartka/plugins/runtime/host_api.dart';
import 'package:kartka/plugins/runtime/plugin_session.dart';

import '../runtime/web_services.dart';

/// The shim in the desktop (web) engine: the sandboxed worker.
/// Run with `fvm flutter test --platform chrome <this file>` (headless).
void main() {
  test('a converted Mangayomi extension runs in the worker', () async {
    final entry = MangayomiEntry.fromJson({
      'id': 9,
      'name': 'W',
      'lang': 'en',
      'baseUrl': 'https://w.test',
      'version': '1.0.0',
      'sourceCodeUrl': 'https://repo.test/w.js',
    });
    const ext = '''
const mangayomiSources = [];
class DefaultExtension extends MProvider {
  getSourcePreferences() {
    return [{key: "d", editTextPreference: {value: "dflt"}}];
  }
  async getPopular(page) {
    console.log("in worker");
    const res = await new Client().get(this.source.baseUrl + "/x");
    const doc = new Document(res.body);
    const a = doc.selectFirst("ul > li a");
    return { list: [{
      name: a.text + new SharedPreferences().get("d") + "a/b".substringAfter("/"),
      link: a.getHref, imageUrl: a.parent.localName }], hasNextPage: false };
  }
}
''';
    final plugin = MangayomiConverter.convert(entry, ext);
    final s = PluginSession(
      manifest: plugin.manifest,
      source: plugin.source,
      services: WebServices(),
      engineFactory: WorkerEngine.new,
    );
    addTearDown(s.dispose);
    expect(await s.call(PluginMethod.popular, [1]), {
      'items': [
        {'url': '/a', 'title': 'Adfltb', 'coverUrl': 'li'},
      ],
      'hasNext': false,
    });
  });
}
