import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/app/feature.dart';
import 'package:kartka/core/source/source_provider.dart';
import 'package:kartka/platform/platform.dart';
import 'package:kartka/sources/mangadex/mangadex_feature.dart';
import 'package:kartka/sources/mangadex/mangadex_image_headers.dart';
import 'package:kartka/sources/mangadex/mangadex_settings_store.dart';
import 'package:kartka/sources/mangadex/mangadex_settings_tile.dart';
import 'package:kartka/sources/mangadex/mangadex_source.dart';

import 'fakes.dart';

/// Platform services this part never touches.
class _Unused implements BlobStore, FilePicker, OAuthRedirect {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  final unused = _Unused();
  final platform = KartkaPlatform(
    http: FakeHttp({}),
    blobs: unused,
    kv: FakeKv(),
    secrets: FakeKv(),
    filePicker: unused,
    oauth: unused,
  );

  test('feature provides the source and the settings store', () async {
    final registry = KartkaRegistry.build(platform, [mangadexFeature]);
    final provider = registry.maybe<SourceProvider>()!;
    final sources = await provider.watch().first;
    expect(sources.single, isA<MangaDexSource>());
    expect(sources.single.ref.id, 'mangadex');
    expect(registry.maybe<MangadexSettingsStore>(), isNotNull);
    expect(registry.maybe<ImageHeaders>(), isA<MangadexImageHeaders>());
    expect(registry.features.single.id, 'source-mangadex');
  });

  testWidgets('settings tile builds the MangaDex tile', (tester) async {
    final registry = KartkaRegistry.build(platform, [mangadexFeature]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Builder(builder: registry.settingsTiles.single)),
      ),
    );
    expect(find.byType(MangadexSettingsTile), findsOneWidget);
  });
}
