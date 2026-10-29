import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/reader/data/reader_prefs.dart';
import 'package:kartka/reader/data/reader_settings.dart';
import 'package:kartka/reader/logic/reader_mode.dart';
import 'package:kartka/reader/state/reader_deps.dart';
import 'package:kartka/reader/ui/page_precache.dart';
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

  Future<void> open(
    WidgetTester tester, {
    int prefetchAhead = 3,
    PagePrecache? precache,
  }) async {
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
            precache:
                precache ?? (provider, _) async => precached.add(provider),
          ),
        ),
      ),
    );
    await ReaderHarness().settle(tester);
  }

  /// Lets the reader sit still long enough for the precache to run.
  Future<void> still(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  testWidgets('decodes the next two pages once the reader is still', (
    tester,
  ) async {
    await open(tester);
    expect(
      [for (var n = 0; n < 6; n++) precachedPage(n)],
      [
        false, true, true, false, false, false, //
      ],
      reason: 'page 0 is on screen: its own image decodes it',
    );
  });

  testWidgets('a swipe decodes nothing in its own frames', (tester) async {
    await open(tester);
    precached.clear();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    // Frames of the page animation: no decode may start in any of them.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 40));
      expect(precached, isEmpty, reason: 'frame $i');
    }
    await still(tester);
    expect(precachedPage(3), isTrue);
    expect(precachedPage(0), isTrue, reason: 'the page behind');
    expect(precachedPage(2), isFalse, reason: 'already decoded earlier');
  });

  testWidgets('swiping on before the pause drops the stale plan', (
    tester,
  ) async {
    await open(tester);
    precached.clear();
    final pager = tester.widget<PageView>(find.byType(PageView)).controller!;
    const quick = Duration(milliseconds: 20);
    pager.animateToPage(1, duration: quick, curve: Curves.linear);
    await tester.pump(const Duration(milliseconds: 100));
    pager.animateToPage(3, duration: quick, curve: Curves.linear);
    await tester.pump(const Duration(milliseconds: 100));
    await still(tester);
    final shown =
        (tester.widget<Image>(find.byType(Image).first).image as ResizeImage)
                .imageProvider
            as MemoryImage;
    final at = [for (var n = 0; n < 6; n++) page(n)]
        .indexWhere((b) => identical(b, shown.bytes));
    expect(at, greaterThan(1), reason: 'the reader moved on');
    // Only the plan of the page the reader stopped on ran: its two pages
    // ahead (the ones before it were decoded when still on page 0). Page 1's
    // plan (2, 3 and the page behind, 0) was dropped.
    expect(
      [for (var n = 0; n < 6; n++) precachedPage(n)],
      [for (var n = 0; n < 6; n++) n > 2 && n > at && n <= at + 2],
    );
  });

  testWidgets('never more than one decode in flight', (tester) async {
    var inFlight = 0;
    var most = 0;
    final gate = Completer<void>();
    await open(
      tester,
      precache: (provider, _) async {
        precached.add(provider);
        inFlight++;
        most = math.max(most, inFlight);
        await gate.future;
        inFlight--;
      },
    );
    expect(precached, hasLength(1), reason: 'the second waits for the first');
    gate.complete();
    await still(tester);
    expect(most, 1);
    expect(precached, hasLength(2));
  });

  testWidgets('decodes at the physical screen width, double when zoomed', (
    tester,
  ) async {
    await open(tester);
    final shown = tester.widget<Image>(find.byType(Image).first).image;
    expect(
      (shown as ResizeImage).width,
      tester.view.physicalSize.width.round(),
    );
    expect(precached.map((p) => (p as ResizeImage).width).toSet(), {
      tester.view.physicalSize.width.round(),
    });
    final center = tester.getCenter(find.byType(Image).first);
    await tester.tapAt(center);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(center);
    await still(tester);
    final zoomed = tester.widget<Image>(find.byType(Image).first).image;
    expect(
      (zoomed as ResizeImage).width,
      (tester.view.physicalSize.width * 2).round(),
    );
  });

  testWidgets('the page shown after a swipe uses the precached key', (
    tester,
  ) async {
    await open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await ReaderHarness().settle(tester);
    final keys = [
      for (final p in precached) await p.obtainKey(ImageConfiguration.empty),
    ];
    final shown = tester.widget<Image>(find.byType(Image).first).image;
    expect(keys, contains(await shown.obtainKey(ImageConfiguration.empty)));
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
