import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/platform/memory/memory_extension_runtime.dart';
import 'package:kartka/platform/memory/memory_fakes.dart';
import 'package:kartka/platform/platform.dart';
import 'package:kartka/sources/device_ext/device_ext_api.dart';
import 'package:kartka/sources/device_ext/keiyoushi_index.dart';

const fire = 'eu.kanade.tachiyomi.extension.all.mangafire';
const atsu = 'eu.kanade.tachiyomi.extension.en.atsumaru';

Map<String, Object?> ext(String pkg, {int code = 1, String id = '1'}) => {
  'pkg': pkg,
  'name': pkg.split('.').last,
  'versionName': '1.6.$code',
  'versionCode': code,
  'sources': [
    {'id': id, 'name': 'S$id', 'lang': 'en', 'supportsLatest': true},
  ],
};

void main() {
  final index = File('test/fixtures/keiyoushi/index.pb').readAsBytesSync();
  final apk = Uint8List.fromList([1, 2, 3]);

  FakeKartkaHttp http({int indexStatus = 200}) => FakeKartkaHttp((r) {
    if (r.url.toString() == keiyoushiIndexUrl) {
      return KartkaResponse(statusCode: indexStatus, bodyBytes: index);
    }
    if (r.url.path.endsWith('.apk')) {
      return KartkaResponse(statusCode: 200, bodyBytes: apk);
    }
    return FakeKartkaHttp.text('', status: 404);
  });

  test('lists the store with installed, outdated and obsolete marks', () async {
    final runtime = FakeExtensionRuntime(
      handler: (m, a) => {
        'installed': [ext(fire), ext('x.gone', id: '9')],
      },
    );
    final api = DeviceExtensionsApi(runtime: runtime, http: http());
    final all = {for (final e in await api.list()) e.pkgName: e};
    expect(all[fire]!.isInstalled, isTrue);
    expect(all[fire]!.hasUpdate, isTrue);
    expect(all[atsu]!.isInstalled, isFalse);
    expect(all[atsu]!.hasUpdate, isFalse);
    expect(all['x.gone']!.isObsolete, isTrue);
    expect(await api.installedPackages(), {fire, 'x.gone'});
    expect(await api.outdatedPackages(), [fire]);
    expect([for (final s in await api.sources()) s.id], ['1', '9']);
    final init = runtime.calls.first;
    expect(init.$1, 'init');
    expect(init.$2['trusted'], [keiyoushiSigningKey]);
    expect(init.$2['userAgent'], kartkaUserAgent);
  });

  test(
    'install downloads the APK, loads it and announces the change',
    () async {
      var installed = <Map<String, Object?>>[];
      final runtime = FakeExtensionRuntime(
        handler: (m, a) {
          if (m == 'install') installed = [ext(atsu, code: 99, id: '7')];
          if (m == 'uninstall') installed = [];
          return {'installed': installed};
        },
      );
      final net = http();
      final api = DeviceExtensionsApi(runtime: runtime, http: net);
      final changes = <List<String>>[];
      api.changes.listen((s) => changes.add([for (final i in s) i.id]));
      final done = await api.install(atsu);
      expect(done.isInstalled, isTrue);
      final sent = runtime.calls.firstWhere((c) => c.$1 == 'install').$2;
      expect(sent['apk'], apk);
      expect(net.requests.last.url.path, endsWith('.apk'));
      await api.updateExtension(atsu);
      await api.installExtension(atsu);
      final gone = await api.uninstall(atsu);
      expect(gone.isInstalled, isFalse);
      final obsolete = await api.uninstall('x.never');
      expect(obsolete.pkgName, 'x.never');
      // With no readable store, a change still reports what is installed.
      final offline = DeviceExtensionsApi(
        runtime: FakeExtensionRuntime(
          handler: (m, a) => {
            'installed': [ext('x.local')],
          },
        ),
        http: FakeKartkaHttp(),
      );
      expect((await offline.uninstall('x.local')).isInstalled, isTrue);
      await pumpEventQueue();
      expect(changes.first, ['7']);
      expect(changes.last, isEmpty);
    },
  );

  test('unknown packages, failed downloads and a failed index throw', () async {
    final runtime = FakeExtensionRuntime();
    final api = DeviceExtensionsApi(runtime: runtime, http: http());
    await expectLater(
      api.install('x.nope'),
      throwsA(isA<ExtensionRuntimeException>()),
    );
    final noApk = DeviceExtensionsApi(
      runtime: runtime,
      http: FakeKartkaHttp(
        (r) => r.url.toString() == keiyoushiIndexUrl
            ? KartkaResponse(statusCode: 200, bodyBytes: index)
            : FakeKartkaHttp.text('', status: 500),
      ),
    );
    await expectLater(noApk.install(fire), throwsA(isA<KartkaHttpException>()));
    var status = 503;
    final flaky = DeviceExtensionsApi(
      runtime: runtime,
      http: FakeKartkaHttp(
        (_) => KartkaResponse(statusCode: status, bodyBytes: index),
      ),
    );
    await expectLater(flaky.list(), throwsA(isA<KartkaHttpException>()));
    status = 200; // the failed fetch is not cached
    expect(await flaky.list(), hasLength(2));
  });
}
