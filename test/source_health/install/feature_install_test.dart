import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kartka/app/feature.dart';
import 'package:kartka/core/source/source_provider.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:kartka/source_health/install/install_ports.dart';
import 'package:kartka/source_health/model/quality_metrics.dart';
import 'package:kartka/source_health/model/source_health_record.dart';
import 'package:kartka/source_health/source_health_feature.dart';
import 'package:kartka/sync/rtdb_reader.dart';

import '../../browse/fakes.dart';
import '../ui/harness.dart';
import 'harness.dart';

class _Suwayomi implements SuwayomiExtensionInstaller {
  @override
  Future<void> installExtension(String pkg) async {}
}

void main() {
  testWidgets('the registered feature lists Install and Open, and Open '
      'browses the source', (tester) async {
    tallSurface(tester);
    const records = [
      SourceHealthRecord(id: 'mangadex', name: 'MangaDex', origin: 'native'),
      SourceHealthRecord(
        id: 'plugin:demo',
        name: 'Demo',
        origin: 'plugin',
        plugin: PluginInstallRef(repo: 'https://repo.test/i.json', id: 'demo'),
      ),
    ];
    final reader = InMemoryRtdbReader({
      'source_health': {
        for (final (i, r) in [...records, suwayomiRecord()].indexed)
          'h$i': r.toJson(),
      },
    });
    final registry = KartkaRegistry.build(memoryPlatform(), [
      sourceHealthFeature,
      (_) => KartkaFeature(
        id: 'others',
        services: [
          reader,
          _Suwayomi(),
          StaticSourceProvider([FakeSource('mangadex')]),
        ],
      ),
    ]);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            body: Builder(builder: registry.tab(KartkaTab.sources)!),
          ),
        ),
        GoRoute(
          path: '/browse/source/:id',
          builder: (_, state) => Text('browsing ${state.pathParameters['id']}'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(theme: buildDarkTheme(), routerConfig: router),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
    expect(installOf('suwayomi:42'), findsOne);
    // No plugin installer is registered, so the plugin source only opens.
    expect(installOf('plugin:demo'), findsNothing);
    expect(openOf('plugin:demo'), findsOne);
    await tester.tap(openOf('mangadex'));
    await tester.pumpAndSettle();
    expect(find.text('browsing mangadex'), findsOne);
  });
}
