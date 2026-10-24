import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/plugins/mangayomi/mangayomi_converter.dart';
import 'package:kartka/plugins/mangayomi/mangayomi_repo_adapter.dart';
import 'package:kartka/plugins/runtime/host_api.dart';
import 'package:kartka/plugins/runtime/plugin_index.dart';

import 'support.dart';

void main() {
  test('converted plugin carries the manifest, entry and wrapped source', () {
    final p = MangayomiConverter.convert(
      testEntry(),
      'class DefaultExtension extends MProvider {}',
    );
    expect(p.manifest.id, 'mangayomi-42');
    expect(p.entry.name, 'Test');
    expect(p.source, contains('const __kmSource = {'));
    expect(p.source, contains('"apiUrl":"https://api.site.test"'));
    expect(p.source, contains('return DefaultExtension;'));
    expect(p.source, isNot(contains('eval(')));
  });

  test('a source without DefaultExtension is rejected', () {
    expect(
      () => MangayomiConverter.convert(testEntry(), 'class Other {}'),
      throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('Test'))),
    );
  });

  test('extension top-level names cannot shadow the entry points', () async {
    const ext = '''
const mangayomiSources = [];
function search() { return "shadowed"; }
const popular = 1;
class DefaultExtension extends MProvider {
  async getPopular(page) {
    return { list: [{ name: this.source.apiUrl, link: "/a" }], hasNextPage: true };
  }
}
''';
    final s = sessionFor(testEntry(), ext, ReplayServices());
    addTearDown(s.dispose);
    final r = await s.call(PluginMethod.popular, [1]);
    expect(r, {
      'items': [
        {'url': '/a', 'title': 'https://api.site.test', 'coverUrl': null},
      ],
      'hasNext': true,
    });
  });

  group('MangayomiRepoAdapter', () {
    final index = Uri.parse('https://repo.test/index.json');

    test('offers convertible entries with their JS URL', () {
      final a = MangayomiRepoAdapter();
      final json = fixtureJson('index.json');
      expect(a.accepts(json), isTrue);
      expect(a.accepts({'plugins': <Object?>[]}), isFalse);
      final offers = a.parse(json, index);
      expect(offers.length, 115);
      final wc = offers.firstWhere((o) => o.manifest.name == 'Weeb Central');
      expect(wc.url.path, endsWith('/javascript/manga/src/en/weebcentral.js'));
      expect(wc.repoUrl, index.toString());
      expect(wc.sha256, isNull);
    });

    test('relative and non-http source URLs', () {
      final a = MangayomiRepoAdapter();
      final offers = a.parse([
        {...testEntry().raw, 'sourceCodeUrl': 'js/a.js'},
        {...testEntry().raw, 'id': 43, 'sourceCodeUrl': 'ftp://x.test/b.js'},
      ], index);
      expect(offers.single.url.toString(), 'https://repo.test/js/a.js');
    });

    test('buildSource converts a parsed offer and refuses unknown ones', () async {
      final a = MangayomiRepoAdapter();
      final offer = a.parse([testEntry().raw], index).single;
      final js = await a.buildSource(
        offer,
        'class DefaultExtension extends MProvider {}',
      );
      expect(js, contains('const __kmExtClass'));
      final stranger = PluginIndexEntry(
        manifest: const PluginManifest(
          id: 'mangayomi-1',
          name: 'n',
          version: '1',
          lang: 'en',
          baseUrl: 'https://b.test',
        ),
        url: Uri.parse('https://b.test/x.js'),
      );
      await expectLater(a.buildSource(stranger, ''), throwsStateError);
    });
  });
}
