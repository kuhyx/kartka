import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/reader/data/reader_prefs.dart';
import 'package:kartka/reader/data/reader_settings.dart';
import 'package:kartka/reader/logic/reader_mode.dart';
import 'package:kartka/reader/state/reader_deps.dart';
import 'package:kartka/reader/ui/reader_screen.dart';

import '../support/fakes.dart';
import 'reader_harness.dart';

void main() {
  late Map<String, Uint8List> bytesByUrl;
  late List<ImageProvider> precached;

  /// Page n's bytes: a distinct copy, so providers identify their page.
  /// Null when the page was never loaded.
  Uint8List? page(int n) => bytesByUrl['https://img.test/c/2/$n.png'];

  bool precachedPage(int n) => precached.any(
    (p) => identical(
      ((p as ResizeImage).imageProvider as MemoryImage).bytes,
      page(n),
    ),
  );

  Future<void> open(WidgetTester tester, {int prefetchAhead = 3}) async {
    bytesByUrl = {};
    precached = [];
    final prefs = ReaderPrefs(MemoryKeyValueStore());
    await prefs.setModeFor('fake|/m/1', ReaderMode.pagedLtr);
    await prefs.saveSettings(ReaderSettings(prefetchAhead: prefetchAhead));
    final source = FakeSource(
      chapterList: harnessChapters,
      pageMap: {'/c/2': fakePages('/c/2', 6)},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          sourceId: source.id,
          mangaUrl: '/m/1',
          chapterUrl: '/c/2',
          system: FakeReaderSystem(),
          onOpenChapter: (_, {atEnd = false}) {},
          onExit: () {},
          deps: ReaderDeps(
            findSource: (_) async => source,
            prefs: prefs,
            loadImage: (p) async => bytesByUrl.putIfAbsent(
              p.imageUrl,
              () => Uint8List.fromList(onePixelPng),
            ),
            precache: (provider, _) async => precached.add(provider),
          ),
        ),
      ),
    );
    await ReaderHarness().settle(tester);
  }

  testWidgets('decodes the next two pages ahead, then the one behind', (
    tester,
  ) async {
    await open(tester);
    expect(
      [for (var n = 0; n < 6; n++) precachedPage(n)],
      [
        true, true, true, false, false, false, //
      ],
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await ReaderHarness().settle(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await ReaderHarness().settle(tester);
    expect(precachedPage(3), isTrue);
    expect(precachedPage(4), isTrue);
    expect(precachedPage(5), isFalse);
  });

  testWidgets('the precached provider is the one the page displays', (
    tester,
  ) async {
    await open(tester);
    final shown = tester.widget<Image>(find.byType(Image).first).image;
    expect(shown, isA<ResizeImage>());
    expect(precached, contains(shown));
    final view = tester.view;
    expect((shown as ResizeImage).width, (view.physicalSize.width * 2).round());
  });

  testWidgets('the pager builds the neighbour page off screen', (tester) async {
    await open(tester);
    expect(
      tester.widget<PageView>(find.byType(PageView)).allowImplicitScrolling,
      isTrue,
    );
  });

  testWidgets('precaching never fetches past the prefetch setting', (
    tester,
  ) async {
    await open(tester, prefetchAhead: 1);
    expect(bytesByUrl.keys, [
      'https://img.test/c/2/0.png',
      'https://img.test/c/2/1.png',
    ]);
    expect(precachedPage(1), isTrue);
  });
}
