import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/app/feature.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/source/source_provider.dart';
import 'package:kartka/platform/http_client.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:kartka/plugins/mangayomi/mangayomi_feature.dart';
import 'package:kartka/plugins/mangayomi/mangayomi_repo_adapter.dart';
import 'package:kartka/plugins/mangayomi/mangayomi_repo_service.dart';
import 'package:kartka/plugins/runtime/engine_interpreter.dart';
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
  test('install Weeb Central from a Mangayomi repo URL and read with it', () async {
    final http = recordedNetwork('weebcentral');
    final registry = KartkaRegistry.build(memoryPlatform(http: http), [
      (env) => pluginsFeature(env, engineFactory: InterpreterEngine.new),
      mangayomiFeature,
    ]);
    expect(registry.maybe<MangayomiRepoAdapter>(), isNotNull);
    final service = registry.maybe<MangayomiRepoService>()!;
    final offers = await service.browse(indexUrl);
    await service.install(offers.firstWhere((o) => o.manifest.name == 'Weeb Central'));

    final provider = registry.maybe<SourceProvider>()!;
    final sources = await provider.watch().firstWhere((l) => l.isNotEmpty);
    final src = sources.single;
    expect(src.ref.id, 'plugin:mangayomi-693275080');
    final popular = await src.popular(1);
    expect(popular.items.first.title, 'Junjou Romantica');
    final hit = (await src.search('solo', 1)).items.first;
    final details = await src.details(hit.url);
    expect(details.title, 'Solo Leveling');
    expect(details.status, MangaStatus.completed);
    final chapters = await src.chapters(hit.url);
    expect(chapters.first.number, 200);
    expect(chapters.first.uploadedAt, DateTime.utc(2024, 9, 7, 17, 4, 15, 717));
    final pages = await src.pages(chapters.last.url);
    expect(pages.length, 12);
    expect(pages.first.index, 0);
    expect(pages.first.headers['Referer'], 'https://weebcentral.com/');
    for (final s in sources) {
      await (s as PluginSource).session.dispose();
    }
  }, timeout: const Timeout(Duration(seconds: 50)));

  test('browse and install failures', () async {
    final http = FakeKartkaHttp((r) {
      if (r.url.path == '/bad.json') return FakeKartkaHttp.text('{nope');
      if (r.url.path == '/kartka.json') return FakeKartkaHttp.text('{"plugins":[]}');
      return FakeKartkaHttp.text('', status: 404);
    });
    final service = MangayomiRepoService(http: http, registrar: () => null);
    await expectLater(service.browse('https://r.test/bad.json'), throwsFormatException);
    await expectLater(service.browse('https://r.test/kartka.json'), throwsFormatException);
    await expectLater(
      service.browse('https://r.test/gone.json'),
      throwsA(isA<KartkaHttpException>()),
    );
    final offer = service.adapter.parse([testEntry().raw], Uri.parse(indexUrl)).single;
    await expectLater(service.install(offer), throwsStateError);
  });
}
