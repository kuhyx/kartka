import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:kartka/sources/suwayomi/suwayomi_client.dart';
import 'package:kartka/sources/suwayomi/suwayomi_extensions.dart';

import 'fakes.dart';

const _spare = 'eu.kanade.tachiyomi.extension.en.weebcentral';
const _mangadex = 'eu.kanade.tachiyomi.extension.all.mangadex';

void main() {
  late FakeKartkaHttp http;
  late int changes;
  SuwayomiExtensionsApi api() => SuwayomiExtensionsApi(
    client: SuwayomiClient(http: http, settings: () => fixtureSettings),
    settings: () => fixtureSettings,
    onChanged: () async => changes++,
  );

  setUp(() {
    http = fixtureHttp([
      'extensions',
      'ext_install',
      'ext_update',
      'ext_uninstall',
    ]);
    changes = 0;
  });

  test('lists installed first, then available by name', () async {
    final list = await api().list();
    expect(list.first.pkgName, _mangadex);
    expect(list.first.isInstalled, isTrue);
    expect(list.first.versionName, '1.6.0');
    expect(
      list.first.iconUrl,
      'http://127.0.0.1:4599/api/v1/extension/icon/$_mangadex',
    );
    final available = list.skip(1).map((e) => e.name).toList();
    expect(
      available,
      [...available]
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())),
    );
    expect(list.skip(1).every((e) => !e.isInstalled), isTrue);
    expect(changes, 0);
  });

  test('installedPackages lists only the installed extensions', () async {
    expect(await api().installedPackages(), {_mangadex});
  });

  test('install, update and uninstall patch by pkgName', () async {
    final installed = await api().install(_spare);
    expect(installed.isInstalled, isTrue);
    final updated = await api().update(_mangadex);
    expect(updated.hasUpdate, isFalse);
    final removed = await api().uninstall(_spare);
    expect(removed.isInstalled, isFalse);
    expect(changes, 3);
    expect(
      [for (final r in bodies(http)) (r['variables']! as Map)['patch']],
      [
        {'install': true},
        {'update': true},
        {'uninstall': true},
      ],
    );
  });

  test('sorting puts pending updates before other installed ones', () {
    SuwayomiExtension ext(String name, {bool inst = false, bool upd = false}) =>
        SuwayomiExtension(
          pkgName: name,
          name: name,
          lang: 'en',
          versionName: '1',
          iconUrl: '',
          isInstalled: inst,
          hasUpdate: upd,
          isObsolete: false,
        );
    final sorted = sortExtensions([
      ext('b'),
      ext('z', inst: true),
      ext('a'),
      ext('y', inst: true, upd: true),
    ]);
    expect(sorted.map((e) => e.name), ['y', 'z', 'a', 'b']);
  });
}
