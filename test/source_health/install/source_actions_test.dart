import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:kartka/plugins/runtime/plugin_manager.dart';
import 'package:kartka/plugins/runtime/plugin_store.dart';
import 'package:kartka/source_health/install/install_ports.dart';
import 'package:kartka/source_health/model/quality_metrics.dart';
import 'package:kartka/source_health/model/source_health_record.dart';
import 'package:kartka/sources/suwayomi/suwayomi_client.dart';
import 'package:kartka/sources/suwayomi/suwayomi_extensions.dart';

import '../../helpers/spoken_icon.dart';
import '../../plugins/runtime/support.dart' as plugin_support;
import '../../sources/suwayomi/fakes.dart';
import 'harness.dart';

const _weebcentral = 'eu.kanade.tachiyomi.extension.en.weebcentral';

/// A Suwayomi extensions API over [http]; a change lists `suwayomi:42`.
SuwayomiExtensionsApi _api(FakeKartkaHttp http, InstallRig Function() rig) =>
    SuwayomiExtensionsApi(
      client: SuwayomiClient(http: http, settings: () => fixtureSettings),
      settings: () => fixtureSettings,
      onChanged: () async => rig().ids.add({'suwayomi:42'}),
    );

class _Gated implements SuwayomiExtensionInstaller {
  final gate = Completer<void>();
  final asked = <String>[];

  @override
  Future<void> installExtension(String pkg) {
    asked.add(pkg);
    return gate.future;
  }
}

void main() {
  testWidgets('a Suwayomi source not on the server installs, then opens', (
    tester,
  ) async {
    final http = fixtureHttp(['ext_install']);
    late final InstallRig rig;
    rig = InstallRig(suwayomi: _api(http, () => rig));
    final record = suwayomiRecord(pkg: _weebcentral);
    await pumpTabWith(tester, rig, [record]);
    expect(openOf(record.id), findsNothing);
    await tester.tap(installOf(record.id));
    await tester.pump();
    await tester.pump();
    final sent = bodies(http).single;
    expect(sent['query'], contains(r'updateExtension(input: {id: $id'));
    expect(sent['variables'], {
      'id': _weebcentral,
      'patch': {'install': true},
    });
    expect(installOf(record.id), findsNothing);
    await tester.tap(openOf(record.id));
    expect(rig.opened, [record.id]);
  });

  testWidgets('an installed Suwayomi source only opens', (tester) async {
    final rig = InstallRig(suwayomi: _Gated());
    final record = suwayomiRecord();
    await pumpTabWith(tester, rig, [record], installed: {record.id});
    expect(installOf(record.id), findsNothing);
    expect(openOf(record.id), findsOne);
  });

  testWidgets('a plugin source installs through the Plugins repo path', (
    tester,
  ) async {
    final http = plugin_support.FakeHttp();
    final store = PluginStore(MemoryKeyValueStore());
    final manager = PluginManager(http: http.client, store: store);
    final rig = InstallRig(plugins: manager);
    const record = SourceHealthRecord(
      id: 'plugin:demo',
      name: 'Demo',
      origin: 'plugin',
      plugin: PluginInstallRef(
        repo: 'https://repo.test/index.json',
        id: 'demo',
      ),
    );
    await pumpTabWith(tester, rig, [record]);
    await tester.tap(installOf(record.id));
    await tester.runAsync(() => pumpEventQueue(times: 50));
    await tester.pump();
    final installed = await tester.runAsync(store.installed);
    expect([for (final p in installed!) p.manifest.id], ['demo']);
    expect(await tester.runAsync(manager.repos), [
      'https://repo.test/index.json',
    ]);
    expect(openOf(record.id), findsOne);
  });

  testWidgets('native, local and legacy sources only open', (tester) async {
    final rig = InstallRig(suwayomi: _Gated(), plugins: _NoPlugins());
    final records = [
      const SourceHealthRecord(id: 'mangadex', name: 'MD', origin: 'native'),
      const SourceHealthRecord(id: 'local', name: 'Local', origin: 'local'),
      const SourceHealthRecord(id: 'plugin:old', name: 'Old', origin: 'plugin'),
      suwayomiRecord(id: 'suwayomi:7', pkg: null),
    ];
    await pumpTabWith(tester, rig, records);
    for (final r in records) {
      expect(installOf(r.id), findsNothing, reason: r.id);
      await tester.tap(openOf(r.id));
    }
    expect(rig.opened, [for (final r in records) r.id]);
  });

  testWidgets('without a registered installer a source only opens', (
    tester,
  ) async {
    final rig = InstallRig();
    final record = suwayomiRecord();
    await pumpTabWith(tester, rig, [record]);
    expect(installOf(record.id), findsNothing);
    expect(openOf(record.id), findsOne);
  });

  testWidgets('installing shows progress and ignores a second tap', (
    tester,
  ) async {
    final gated = _Gated();
    final rig = InstallRig(suwayomi: gated);
    final record = suwayomiRecord();
    await pumpTabWith(tester, rig, [record]);
    await tester.tap(installOf(record.id));
    await tester.pump();
    expect(installingOf(record.id), findsOne);
    expect(find.byType(CircularProgressIndicator), findsOne);
    await tester.tap(installingOf(record.id));
    expect(gated.asked, [atsumaruPkg]);
    gated.gate.complete();
    await tester.pump();
    await tester.pump();
    expect(openOf(record.id), findsOne);
  });

  testWidgets('a failed install shows a redacted snackbar and logs it', (
    tester,
  ) async {
    const secretUrl = 'http://127.0.0.1:4567/api/graphql?token=s3cret';
    final http = FakeKartkaHttp(
      (_) => FakeKartkaHttp.text(
        jsonEncode({
          'errors': [
            {'message': 'extension download failed: $secretUrl'},
          ],
        }),
      ),
    );
    late final InstallRig rig;
    rig = InstallRig(suwayomi: _api(http, () => rig));
    final record = suwayomiRecord();
    await pumpTabWith(tester, rig, [record]);
    await tester.tap(installOf(record.id));
    await tester.pump();
    await tester.pump();
    final snack = find.byType(SnackBar);
    expect(
      find.descendant(of: snack, matching: spokenIcon('Install failed')),
      findsOne,
    );
    final shown = tester
        .widget<Text>(find.descendant(of: snack, matching: find.byType(Text)))
        .data!;
    expect(shown, 'SuwayomiException: extension download failed: <url>');
    expect(shown, isNot(contains('http')));
    expect(shown, isNot(contains('s3cret')));
    expect(installOf(record.id), findsOne);
    final entries = (await tester.runAsync(rig.entries))!;
    expect(entries.single.kind, 'sources.install');
    expect(entries.single.sourceId, record.id);
    expect(entries.single.error, contains('download failed: <url>'));
    final line = jsonEncode(entries.single.toJson());
    expect(line, isNot(contains('http')));
    expect(line, isNot(contains('?')));
    expect(line, isNot(contains('s3cret')));
  });

  testWidgets('the detail page installs and opens too', (tester) async {
    final gated = _Gated();
    final rig = InstallRig(suwayomi: gated);
    final record = suwayomiRecord();
    await pumpDetailWith(tester, rig, record);
    await tester.tap(installOf(record.id));
    gated.gate.complete();
    await tester.pump();
    await tester.pump();
    await tester.tap(openOf(record.id));
    expect(rig.opened, [record.id]);
  });
}

class _NoPlugins implements PluginRepoInstaller {
  @override
  Future<void> installPlugin({required String repo, required String id}) =>
      throw StateError('a record without a plugin ref never installs');
}
