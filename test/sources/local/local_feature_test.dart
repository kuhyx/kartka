import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/app/feature.dart';
import 'package:kartka/core/source/source_provider.dart';
import 'package:kartka/sources/local/import_local_tile.dart';
import 'package:kartka/sources/local/local_feature.dart';
import 'package:kartka/sources/local/local_library.dart';

import 'fakes.dart';

void main() {
  test('provides the local source and its library as services', () async {
    final registry = KartkaRegistry.build(memoryPlatform(), [localFeature]);
    expect(registry.features.single.id, 'source-local');
    final sources = await registry.all<SourceProvider>().single.watch().first;
    expect(sources.single.ref.id, 'local');
    expect(registry.maybe<LocalLibrary>(), isNotNull);
  });

  testWidgets('adds the "Import local files" settings tile', (t) async {
    final registry = KartkaRegistry.build(memoryPlatform(), [localFeature]);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Builder(builder: registry.settingsTiles.single)),
      ),
    );
    expect(find.byType(ImportLocalTile), findsOneWidget);
    expect(find.text('Import local files'), findsOneWidget);
  });
}
