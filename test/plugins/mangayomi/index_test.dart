import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/plugins/mangayomi/mangayomi_entry.dart';
import 'package:kartka/plugins/mangayomi/mangayomi_index.dart';

import 'support.dart';

Map<String, Object?> entryJson([Map<String, Object?> over = const {}]) => {
  'id': 7,
  'name': 'X',
  'lang': 'en',
  'baseUrl': 'https://x.test',
  'version': '1.2.0',
  'sourceCodeUrl': 'https://repo.test/x.js',
  'sourceCodeLanguage': 1,
  'itemType': 0,
  ...over,
};

void main() {
  group('MangayomiIndex', () {
    test('parses the real repo index: only JS manga with a .js file', () {
      final json = fixtureJson('index.json');
      expect(MangayomiIndex.looksLike(json), isTrue);
      final entries = MangayomiIndex.parse(json);
      expect(entries.length, 115);
      expect(entries.map((e) => e.pluginId).toSet().length, 115);
      final asura = entries.first;
      expect(asura.name, 'Asura Scans');
      expect(asura.lang, 'en');
      expect(asura.toManifest().id, 'mangayomi-524070078');
      expect(asura.toManifest().sourceId, 'plugin:mangayomi-524070078');
      expect(asura.toManifest().version, '0.1.7');
      expect(asura.toManifest().icon, endsWith('en.asurascans.png'));
      final dex = entries.where((e) => e.name == 'MangaDex');
      expect(dex.length, greaterThan(40));
      expect(dex.first.apiUrl, 'https://api.mangadex.org');
    });

    test('skips Dart, anime, novel, non-.js and malformed entries', () {
      final json = [
        entryJson(),
        entryJson({'sourceCodeLanguage': 0}),
        entryJson({'itemType': 1}),
        entryJson({'sourceCodeUrl': 'https://repo.test/x.dart'}),
        entryJson({'sourceCodeUrl': ''}),
        entryJson({'name': null}),
        entryJson({'id': '7'}),
      ];
      expect(MangayomiIndex.parse(json).map((e) => e.id), [7]);
    });

    test('rejects other index shapes', () {
      for (final bad in <Object?>[
        {'plugins': <Object?>[]},
        <Object?>[],
        [
          {'id': 1},
        ],
        'x',
        null,
      ]) {
        expect(MangayomiIndex.looksLike(bad), isFalse);
        expect(() => MangayomiIndex.parse(bad), throwsFormatException);
      }
    });

    test('index URL from an index URL, repo root or owner/repo', () {
      expect(
        MangayomiIndex.indexUrl('entityJY/mangayomi-extensions-eJ').toString(),
        'https://raw.githubusercontent.com/entityJY/mangayomi-extensions-eJ/main/index.json',
      );
      expect(
        MangayomiIndex.indexUrl(' https://a.test/repo/index.json ').toString(),
        'https://a.test/repo/index.json',
      );
      expect(
        MangayomiIndex.indexUrl('https://a.test/repo').toString(),
        'https://a.test/repo/index.json',
      );
      expect(
        MangayomiIndex.indexUrl('https://a.test/repo/').toString(),
        'https://a.test/repo/index.json',
      );
    });
  });

  group('MangayomiEntry', () {
    test('optional fields default and raw is kept whole', () {
      final e = MangayomiEntry.fromJson(
        entryJson({'apiUrl': null, 'iconUrl': '', 'isNsfw': true}),
      );
      expect(e.apiUrl, '');
      expect(e.iconUrl, isNull);
      expect(e.isNsfw, isTrue);
      expect(e.hasCloudflare, isFalse);
      expect(e.raw['sourceCodeLanguage'], 1);
      expect(() => e.raw['x'] = 1, throwsUnsupportedError);
    });

    test('missing required fields are FormatExceptions', () {
      expect(
        () => MangayomiEntry.fromJson(entryJson({'baseUrl': ''})),
        throwsFormatException,
      );
      expect(
        () => MangayomiEntry.fromJson(entryJson({'id': null})),
        throwsFormatException,
      );
    });

    test('isConvertible treats a missing itemType as manga', () {
      expect(MangayomiEntry.isConvertible(entryJson({'itemType': null})), isTrue);
      expect(
        MangayomiEntry.isConvertible(entryJson({'sourceCodeUrl': 3})),
        isFalse,
      );
    });
  });
}
