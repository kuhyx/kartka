import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kartka/app/feature.dart';
import 'package:kartka/app/routes.dart';
import 'package:kartka/browse/browse_feature.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/source/source_provider.dart';
import 'package:kartka/core/updates/chapter_addition_sink.dart';
import 'package:kartka/library/library_feature.dart';
import 'package:kartka/library/library_repositories.dart';
import 'package:kartka/library/ports.dart';
import 'package:kartka/platform/http_client.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:kartka/updates/updates_feature.dart';

import '../browse/fakes.dart';
import '../browse/ui/harness.dart';

ChapterInfo _ch(int n) =>
    ChapterInfo(url: '/c/$n', name: 'Ch. $n', number: n.toDouble());

final MangaKey _key = mangaKeyOf('mangadex', '/m/1');

({KartkaRegistry reg, FakeSource src}) _build() {
  final src = FakeSource(
    'mangadex',
    chapters: [_ch(4), _ch(3), _ch(2), _ch(1)],
  );
  // The list a past visit stored: the baseline the detail open diffs.
  final kv = MemoryKeyValueStore({
    'browse.chapters.${mangaKeyHash(_key)}': jsonEncode([
      _ch(2).toJson(),
      _ch(1).toJson(),
    ]),
  });
  final http = FakeKartkaHttp(
    (_) => KartkaResponse(statusCode: 200, bodyBytes: onePixelPng),
  );
  final reg = KartkaRegistry.build(memoryPlatform(http: http, kv: kv), [
    libraryFeature,
    (_) => KartkaFeature(
      id: 'fixtures',
      services: [
        StaticSourceProvider([src]),
      ],
    ),
    browseFeature,
    updatesFeature,
  ]);
  return (reg: reg, src: src);
}

Future<void> _addToLibrary(KartkaRegistry reg) =>
    reg.maybe<LibraryRepositories>()!.library.upsert(
      LibraryEntry(
        key: _key,
        sourceId: 'mangadex',
        mangaUrl: '/m/1',
        title: 'Monster',
        coverUrl: 'https://img.test/monster.jpg',
        addedAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
    );

void main() {
  test('fills the Updates tab and offers the updater and feed sink', () {
    final reg = _build().reg;
    expect(reg.tab(KartkaTab.updates), isNotNull);
    expect(reg.maybe<LibraryUpdater>(), isNotNull);
    expect(reg.all<ChapterAdditionSink>(), hasLength(1));
  });

  testWidgets('a detail open feeds the tab; update-all after finds none', (
    t,
  ) async {
    final (:reg, :src) = _build();
    await _addToLibrary(reg);
    final tab = reg.tab(KartkaTab.updates)!;
    final router = GoRouter(
      initialLocation: mangaRoute('mangadex', '/m/1'),
      routes: [
        GoRoute(path: '/', builder: (context, _) => tab(context)),
        ...reg.routes,
      ],
    );
    await t.pumpWidget(MaterialApp.router(routerConfig: router));
    await t.pumpAndSettle();
    // The detail page fetched and stored the grown list itself.
    expect(src.calls.where((c) => c.startsWith('chapters')), hasLength(1));

    router.go('/');
    await t.pumpAndSettle();
    expect(find.text('Monster'), findsOneWidget);
    expect(find.text('Ch. 3'), findsOneWidget);
    expect(find.text('Ch. 4'), findsOneWidget);

    // The baseline moved, so update-all finds nothing new now.
    await t.tap(find.byTooltip('Check for updates'));
    await t.pumpAndSettle();
    expect(find.text('No new chapters'), findsOneWidget);
    expect(src.calls.where((c) => c.startsWith('chapters')), hasLength(2));
  });

  testWidgets('without the library feature the tab fails loudly', (t) async {
    final reg = KartkaRegistry.build(memoryPlatform(), [updatesFeature]);
    await t.pumpWidget(Builder(builder: reg.tab(KartkaTab.updates)!));
    expect('${t.takeException()}', contains('library'));
  });

  test('without a checker every manga counts as failed', () async {
    final reg = KartkaRegistry.build(memoryPlatform(), [
      libraryFeature,
      updatesFeature,
    ]);
    await _addToLibrary(reg);
    final summary = await reg.maybe<LibraryUpdater>()!.updateAll();
    expect(summary.message, 'No new chapters · 1 failed');
  });
}
