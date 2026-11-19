import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/reader/data/reader_prefs.dart';
import 'package:kartka/reader/data/reader_settings.dart';
import 'package:kartka/reader/logic/reader_mode.dart';
import 'package:kartka/reader/state/reader_deps.dart';
import 'package:kartka/reader/ui/reader_screen.dart';
import 'package:material_ui/material_ui.dart';

import '../support/fakes.dart';
import 'reader_harness.dart';

/// The server rate-limits a source: four pages at once took up to 1.95 s
/// each, one at a time 0.15 s (28fffd0a). Neither the pager's off-screen
/// neighbours, the webtoon list's cache extent nor the decode plan may
/// start a fetch beside the queue's one.
void main() {
  late int inFlight;
  late int most;
  late List<String> started;

  Future<void> open(WidgetTester tester, ReaderMode mode) async {
    inFlight = 0;
    most = 0;
    started = [];
    final prefs = ReaderPrefs(MemoryKeyValueStore());
    await prefs.setModeFor('fake|/m/1', mode);
    await prefs.saveSettings(const ReaderSettings());
    final source = FakeSource(
      chapterList: harnessChapters,
      pageMap: {'/c/2': fakePages('/c/2', 12)},
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
            loadImage: (p) async {
              started.add(p.imageUrl);
              inFlight++;
              most = math.max(most, inFlight);
              await Future<void>.delayed(const Duration(milliseconds: 150));
              inFlight--;
              return onePixelPng;
            },
            precache: (_, _) async {},
          ),
        ),
      ),
    );
  }

  Future<void> run(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  for (final mode in [ReaderMode.pagedLtr, ReaderMode.webtoon]) {
    testWidgets('${mode.name}: one page fetch in flight at a time', (
      tester,
    ) async {
      await open(tester, mode);
      await run(tester);
      expect(started, isNotEmpty);
      expect(most, 1);
    });
  }

  testWidgets('a turn and a jump still fetch one page at a time', (
    tester,
  ) async {
    await open(tester, ReaderMode.pagedLtr);
    await run(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await run(tester);
    tester
        .widget<PageView>(find.byType(PageView))
        .controller!
        // Item 0 is the previous-chapter slot: item 10 is page 9.
        .jumpToPage(10);
    await run(tester);
    expect(most, 1);
    expect(started, contains('https://img.test/c/2/9.png'));
    expect(find.byType(Image), findsWidgets);
  });

  testWidgets('a jump starts its page at once, behind one old look-ahead', (
    tester,
  ) async {
    await open(tester, ReaderMode.pagedLtr);
    await tester.pump(const Duration(milliseconds: 200));
    tester
        .widget<PageView>(find.byType(PageView))
        .controller!
        // Item 0 is the previous-chapter slot: item 10 is page 9.
        .jumpToPage(10);
    await tester.pump();
    expect(started.last, 'https://img.test/c/2/9.png');
    expect(most, lessThanOrEqualTo(2), reason: 'an old fetch cannot stop');
    await run(tester);
  });
}
