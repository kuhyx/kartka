import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/plugins/runtime/host_api.dart';
import 'package:kartka/plugins/runtime/plugin_index.dart';
import 'package:kartka/plugins/runtime/plugin_languages.dart';
import 'package:kartka/plugins/runtime/plugin_manager.dart';
import 'package:kartka/plugins/runtime/plugin_store.dart';
import 'package:kartka/plugins/runtime/plugins_screen.dart';

import 'support.dart';

AvailablePlugin _offer(String id, String lang, [PluginAvailability? state]) =>
    AvailablePlugin(
      PluginIndexEntry(
        manifest: PluginManifest(
          id: id,
          name: id,
          version: '1.0.0',
          lang: lang,
          baseUrl: 'https://$id.test',
        ),
        url: Uri.parse('https://$id.test/p.js'),
      ),
      state ?? PluginAvailability.available,
    );

void main() {
  const repo = 'https://repo.test/index.json';
  late FakeHttp http;
  late MemoryKeyValueStore kv;

  setUp(() {
    http = FakeHttp();
    kv = MemoryKeyValueStore();
  });

  // Demo Site stays English; No Hash becomes [nohash].
  Future<void> open(
    WidgetTester t, {
    String nohash = 'ja',
    String? demo,
  }) async {
    var index = fixture('index.json').replaceFirst(
      '"version": "0.1.0", "lang": "en"',
      '"version": "0.1.0", "lang": "$nohash"',
    );
    if (demo != null) index = index.replaceFirst('"en"', '"$demo"');
    http.overrides[repo] = (status: 200, body: index);
    await PluginStore(kv).setRepos([repo]);
    final manager = PluginManager(http: http.client, store: PluginStore(kv));
    await t.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: PluginsScreen(key: UniqueKey(), manager: manager),
      ),
    );
    await t.pumpAndSettle();
  }

  Future<void> toggle(WidgetTester t, String label) async {
    await t.tap(find.byKey(const Key('plugin-languages')));
    await t.pumpAndSettle();
    await t.tap(find.text(label));
    await t.pumpAndSettle();
    await t.tap(find.text('Done'));
    await t.pumpAndSettle();
  }

  test('defaults to every-language and English plugins', () {
    expect(kDefaultPluginLanguages, ['all', 'en']);
    final shown = shownPlugins([
      _offer('a', 'all'),
      _offer('m', 'multi'),
      _offer('e', 'EN'),
      _offer('j', 'ja'),
      _offer('u', 'ja', PluginAvailability.updatable),
    ], kDefaultPluginLanguages);
    // An installed plugin stays listed so its Update is never hidden.
    expect([for (final p in shown) p.entry.manifest.id], ['a', 'm', 'e', 'u']);
    expect(
      hiddenByLanguageMessage(1),
      '1 plugin is in other languages. Pick more in Languages.',
    );
    expect(pluginLanguageCounts([_offer('a', 'multi'), _offer('b', 'all')]), {
      'all': 2,
    });
  });

  test('the store keeps the selection, unset by default', () async {
    final store = PluginStore(kv);
    expect(await store.languages(), isNull);
    await store.setLanguages(['ja']);
    expect(await store.languages(), ['ja']);
  });

  testWidgets('other languages are hidden until picked, and stay', (t) async {
    await open(t);
    expect(find.text('Demo Site'), findsOneWidget);
    expect(find.text('No Hash'), findsNothing);
    expect(find.text('Languages: All languages, English'), findsOneWidget);

    await t.tap(find.byKey(const Key('plugin-languages')));
    await t.pumpAndSettle();
    expect(find.text('1 plugin'), findsNWidgets(2));
    await t.tap(find.text('Done'));
    await t.pumpAndSettle();

    await toggle(t, 'Japanese');
    expect(find.text('No Hash'), findsOneWidget);
    expect(await PluginStore(kv).languages(), ['all', 'en', 'ja']);

    await open(t);
    expect(find.text('No Hash'), findsOneWidget);
    await toggle(t, 'English');
    expect(find.text('Demo Site'), findsNothing);
    expect(find.text('Languages: All languages, Japanese'), findsOneWidget);
  });

  testWidgets('says so when every plugin is filtered out', (t) async {
    await open(t, demo: 'ko');
    expect(find.text('Demo Site'), findsNothing);
    expect(
      find.text('2 plugins are in other languages. Pick more in Languages.'),
      findsOneWidget,
    );
    await toggle(t, 'All languages');
    await toggle(t, 'English');
    expect(find.text('Languages: none'), findsOneWidget);
    await t.tap(find.byKey(const Key('plugin-languages')));
    await t.pumpAndSettle();
    expect(find.text('2 plugins'), findsNothing);
    expect(find.text('Korean'), findsOneWidget);
  });
}
