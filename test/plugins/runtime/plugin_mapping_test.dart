import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/plugins/runtime/host_api.dart';
import 'package:kartka/plugins/runtime/plugin_mapping.dart';

void main() {
  const m = PluginMapper('demo');

  test('page maps items, fills the source id and hasNext', () {
    final p = m.page(PluginMethod.popular, {
      'items': [
        {'url': '/m/1', 'title': 'One', 'coverUrl': 'c'},
        {'url': '/m/2', 'title': 'Two'},
      ],
      'hasNext': true,
    });
    expect(p.hasNext, true);
    expect(p.items.first.sourceId, 'plugin:demo');
    expect(p.items.first.key, 'plugin:demo|/m/1');
    expect(p.items.last.coverUrl, isNull);
    expect(m.page(PluginMethod.latest, {}).items, isEmpty);
  });

  test('details maps every field, status by name or Tachiyomi code', () {
    final d = m.details({
      'url': '/m/1',
      'title': 'One',
      'authors': ['A', 3],
      'description': 'd',
      'genres': ['g'],
      'status': 'completed',
      'trackerIds': {'anilist': 123},
    });
    expect(d.authors, ['A', '3']);
    expect(d.status, MangaStatus.completed);
    expect(d.trackerIds, {'anilist': '123'});
    expect(
      m.details({'url': 'u', 'title': 't', 'status': 1}).status,
      MangaStatus.ongoing,
    );
    expect(
      m.details({'url': 'u', 'title': 't', 'status': 99}).status,
      MangaStatus.unknown,
    );
    expect(m.details({'url': 'u', 'title': 't'}).authors, isEmpty);
  });

  test('chapters accept numbers, strings, epoch ms and ISO dates', () {
    final c = m.chapters([
      {
        'url': 'a',
        'name': 'A',
        'number': 2,
        'uploadedAt': 1000,
        'scanlator': 's',
      },
      {
        'url': 'b',
        'name': 'B',
        'number': '1.5',
        'uploadedAt': '2026-01-02T00:00:00Z',
      },
      {'url': 'c', 'name': 'C', 'number': 'x', 'uploadedAt': true},
    ]);
    expect(c[0].number, 2.0);
    expect(
      c[0].uploadedAt,
      DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
    );
    expect(c[0].scanlator, 's');
    expect(c[1].number, 1.5);
    expect(c[1].uploadedAt!.year, 2026);
    expect(c[2].number, isNull);
    expect(c[2].uploadedAt, isNull);
  });

  test('pages are indexed by position and carry headers', () {
    final p = m.pages([
      {
        'imageUrl': 'x',
        'headers': {'R': 1},
      },
      {'imageUrl': 'y'},
    ]);
    expect(p.map((e) => e.index), [0, 1]);
    expect(p.first.headers, {'R': '1'});
    expect(p.last.headers, isEmpty);
  });

  test('malformed results become PluginException naming plugin and method', () {
    void bad(void Function() f, PluginMethod method) => expect(
      f,
      throwsA(
        isA<PluginException>()
            .having((e) => e.pluginId, 'id', 'demo')
            .having((e) => e.method, 'method', method),
      ),
    );
    bad(() => m.page(PluginMethod.search, 'x'), PluginMethod.search);
    bad(
      () => m.page(PluginMethod.popular, <String, Object?>{'items': 3}),
      PluginMethod.popular,
    );
    bad(
      () => m.page(PluginMethod.popular, {
        'items': [<String, Object?>{}],
      }),
      PluginMethod.popular,
    );
    bad(() => m.details(null), PluginMethod.details);
    bad(() => m.chapters({}), PluginMethod.chapters);
    bad(
      () => m.pages([
        {'imageUrl': ''},
      ]),
      PluginMethod.pages,
    );
    expect(m.chapters(null), isEmpty);
  });
}
