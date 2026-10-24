import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/plugins/runtime/host_api.dart';
import 'package:kartka/plugins/runtime/plugin_session.dart';

import 'support.dart';

PluginSession session(String body) => sessionFor(
  testEntry(),
  'const mangayomiSources = [];\n'
  'class DefaultExtension extends MProvider {\n$body\n}',
  ReplayServices(),
);

void main() {
  test('listing mapping, title fallback and supportsLatest false', () async {
    final s = session('''
get supportsLatest() { return false; }
async getPopular(p) { return { list: [{link: "/a"}, {name: "no link"}, null,
  {name: "B", link: "/b", imageUrl: "c.jpg"}], hasNextPage: 1 }; }
getFilterList() { throw new Error("none"); }
async search(q, p, f) { return { list: [{name: q + f.length, link: "/q"}] }; }
async getDetail(url) { return { genre: "A, B", author: "X, Y", artist: "Y, Z" }; }
''');
    addTearDown(s.dispose);
    expect(await s.call(PluginMethod.popular, [1]), {
      'items': [
        {'url': '/a', 'title': '/a', 'coverUrl': null},
        {'url': '/b', 'title': 'B', 'coverUrl': 'c.jpg'},
      ],
      'hasNext': true,
    });
    expect(await s.call(PluginMethod.latest, [1]), {
      'items': <Object?>[],
      'hasNext': false,
    });
    expect(await s.call(PluginMethod.search, ['q', 1]), {
      'items': [
        {'url': '/q', 'title': 'q0', 'coverUrl': null},
      ],
      'hasNext': false,
    });
    expect(await s.call(PluginMethod.details, ['/b']), {
      'url': '/b',
      'title': 'B',
      'coverUrl': 'c.jpg',
      'authors': ['X', 'Y', 'Z'],
      'description': null,
      'genres': ['A', 'B'],
      'status': 'unknown',
    });
    expect(
      await s.call(PluginMethod.details, ['/new']),
      containsPair('title', '/new'),
    );
  });

  test('a throwing supportsLatest counts as supported', () async {
    final s = session('''
get supportsLatest() { throw new Error("x"); }
async getLatestUpdates(p) { return { list: [], hasNextPage: false }; }
''');
    addTearDown(s.dispose);
    expect(await s.call(PluginMethod.latest, [1]), {
      'items': <Object?>[],
      'hasNext': false,
    });
  });

  test('getDetail is memoised per url and a failure is not cached', () async {
    final s = session('''
async getDetail(url) {
  globalThis.n = (globalThis.n || 0) + 1;
  if (url === "/bad" && globalThis.n < 3) throw new Error("flaky");
  return { name: "N" + globalThis.n, status: 2, episodes: [
    {name: "Episode 7", url: "/e7", dateUpload: "NaN"},
    {name: "Vol.2 Ch.3.5 - x", url: "/c35", dateUpload: "1700000000000", scanlator: "S"},
    {name: "Vol.4", url: "/v4", dateUpload: ""},
    {name: "Special #12", url: "/s12"},
    {name: "", url: "/blank"},
    {name: "none", url: ""},
  ] };
}
''');
    addTearDown(s.dispose);
    final d = await s.call(PluginMethod.details, ['/m']);
    expect((d! as Map)['status'], 'onHiatus');
    final chapters = await s.call(PluginMethod.chapters, ['/m']);
    expect((d as Map)['title'], 'N1');
    expect(chapters, [
      {
        'url': '/e7',
        'name': 'Episode 7',
        'number': 7,
        'uploadedAt': null,
        'scanlator': null,
      },
      {
        'url': '/c35',
        'name': 'Vol.2 Ch.3.5 - x',
        'number': 3.5,
        'uploadedAt': '2023-11-14T22:13:20.000Z',
        'scanlator': 'S',
      },
      {
        'url': '/v4',
        'name': 'Vol.4',
        'number': null,
        'uploadedAt': null,
        'scanlator': null,
      },
      {
        'url': '/s12',
        'name': 'Special #12',
        'number': 12,
        'uploadedAt': null,
        'scanlator': null,
      },
      {
        'url': '/blank',
        'name': '/blank',
        'number': null,
        'uploadedAt': null,
        'scanlator': null,
      },
    ]);
    await expectLater(
      s.call(PluginMethod.details, ['/bad']),
      throwsA(isA<PluginException>()),
    );
    expect(
      await s.call(PluginMethod.details, ['/bad']),
      containsPair('title', 'N3'),
    );
    for (var i = 0; i < 9; i++) {
      await s.call(PluginMethod.details, ['/k$i']);
    }
    // '/m' was evicted (cache holds 8), so it is fetched again.
    expect(
      await s.call(PluginMethod.details, ['/m']),
      containsPair('title', 'N13'),
    );
  });

  test('pages: strings and objects, de-duplicated, headers layered', () async {
    final s = session('''
getHeaders(url) { return { Referer: "https://r.test/", "X-N": 1 }; }
async getPageList(url) { return [" https://i.test/1.jpg ", null,
  {url: "https://i.test/2.jpg", headers: {Referer: "https://own.test/"}},
  "https://i.test/1.jpg", {url: ""}, {url: "https://i.test/3.jpg"}]; }
''');
    addTearDown(s.dispose);
    expect(await s.call(PluginMethod.pages, ['/c']), [
      {
        'imageUrl': 'https://i.test/1.jpg',
        'headers': {'Referer': 'https://r.test/', 'X-N': '1'},
      },
      {
        'imageUrl': 'https://i.test/2.jpg',
        'headers': {'Referer': 'https://own.test/', 'X-N': '1'},
      },
      {
        'imageUrl': 'https://i.test/3.jpg',
        'headers': {'Referer': 'https://r.test/', 'X-N': '1'},
      },
    ]);
  });

  test('pages without usable getHeaders, and unimplemented methods', () async {
    for (final h in ['throw new Error("x");', 'return "nope";']) {
      final s = session('''
getHeaders(url) { $h }
async getPageList(url) { return ["https://i.test/1.jpg"]; }
''');
      expect(await s.call(PluginMethod.pages, ['/c']), [
        {'imageUrl': 'https://i.test/1.jpg', 'headers': <String, Object?>{}},
      ]);
      await s.dispose();
    }
    final s = session('');
    addTearDown(s.dispose);
    for (final m in PluginMethod.values) {
      await expectLater(
        s.call(m, m == PluginMethod.search ? ['q', 1] : [1]),
        throwsA(
          isA<PluginException>().having(
            (e) => e.message,
            'm',
            contains('not implemented'),
          ),
        ),
      );
    }
  });
}
