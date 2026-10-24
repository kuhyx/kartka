import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/app/feature.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/source/source_provider.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:kartka/plugins/mangayomi/mangayomi_feature.dart';
import 'package:kartka/plugins/runtime/engine_quickjs.dart';
import 'package:kartka/plugins/runtime/plugin_manager.dart';
import 'package:kartka/plugins/runtime/plugin_repo_adapter.dart';
import 'package:kartka/plugins/runtime/plugin_source.dart';
import 'package:kartka/plugins/runtime/plugins_feature.dart';

import 'support.dart';

const indexUrl = 'https://repo.test/index.json';

/// A fake network serving the repo index, the extension JS (at the URL the
/// index names) and every recorded site response.
FakeKartkaHttp recordedNetwork(String name) {
  final rec = recording(name);
  final routes = <String, Exchange>{
    for (final e in rec.exchanges) '${e.method} ${Uri.parse(e.url)}': e,
  };
  final index = File('$fixtureDir/index.json').readAsStringSync();
  return FakeKartkaHttp((r) {
    if ('${r.url}' == indexUrl) return FakeKartkaHttp.text(index);
    if ('${r.url}' == rec.entry.sourceCodeUrl) {
      return FakeKartkaHttp.text(rec.exchanges.first.body);
    }
    final e = routes['${r.method} ${r.url}'];
    if (e == null) return FakeKartkaHttp.text('unrecorded', status: 599);
    return FakeKartkaHttp.text(e.body, status: e.status, headers: e.headers);
  });
}

void main() {
  test(
    'add a Mangayomi repo on the Plugins manager, install Weeb Central, read',
    () async {
      final registry = KartkaRegistry.build(
        memoryPlatform(http: recordedNetwork('weebcentral')),
        [
          (env) => pluginsFeature(env, engineFactory: QuickJsEngine.new),
          mangayomiFeature,
        ],
      );
      expect(registry.all<PluginRepoAdapter>(), hasLength(1));
      final manager = registry.maybe<PluginManager>()!;
      await manager.addRepo(indexUrl);
      final offers = (await manager.available()).plugins;
      expect(offers.length, 115);
      final wc = offers.firstWhere(
        (o) => o.entry.manifest.name == 'Weeb Central',
      );
      expect(wc.availability, PluginAvailability.available);
      await manager.install(wc.entry);

      final provider = registry.maybe<SourceProvider>()!;
      final sources = await provider.watch().firstWhere((l) => l.isNotEmpty);
      final src = sources.single as PluginSource;
      addTearDown(src.session.dispose);
      expect(src.ref.id, 'plugin:mangayomi-693275080');
      final popular = await src.popular(1);
      expect(popular.items.first.title, 'Junjou Romantica');
      final hit = (await src.search('solo', 1)).items.first;
      final details = await src.details(hit.url);
      expect(details.title, 'Solo Leveling');
      expect(details.status, MangaStatus.completed);
      final chapters = await src.chapters(hit.url);
      expect(chapters.first.number, 200);
      expect(
        chapters.first.uploadedAt,
        DateTime.utc(2024, 9, 7, 17, 4, 15, 717),
      );
      final pages = await src.pages(chapters.last.url);
      expect(pages.length, 12);
      expect(pages.first.index, 0);
      expect(pages.first.headers['Referer'], 'https://weebcentral.com/');
    },
    timeout: const Timeout(Duration(seconds: 50)),
  );
}
