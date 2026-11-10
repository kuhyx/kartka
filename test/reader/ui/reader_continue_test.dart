import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/reader/logic/reader_mode.dart';
import 'package:kartka/reader/ui/chapter_transition.dart';

import '../../helpers/spoken_icon.dart';
import '../support/fakes.dart';
import 'reader_harness.dart';

/// Chapter 2 (4 pages); chapter 3 (2 pages) answers once [gate] completes.
class _SlowNext extends FakeSource {
  new()
    : super(
        chapterList: harnessChapters,
        pageMap: {'/c/2': fakePages('/c/2', 4)},
      );

  /// Made inside the test body: a completer from setUp would complete on
  /// the real event loop, which the widget tester's fake clock never runs.
  Completer<List<PageRef>> gate = Completer();

  @override
  Future<List<PageRef>> pages(String chapterUrl) async {
    if (chapterUrl == '/c/3') return await gate.future;
    return await super.pages(chapterUrl);
  }
}

void main() {
  late ReaderHarness h;
  late _SlowNext source;

  setUp(() {
    source = _SlowNext();
    h = ReaderHarness(source: source);
  });

  Future<void> open(WidgetTester tester, ReaderMode mode) async {
    source.gate = Completer();
    await h.prefs.setModeFor('fake|/m/1', mode);
    await h.pump(tester);
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey k, int n) async {
    for (var i = 0; i < n; i++) {
      await tester.sendKeyEvent(k);
      await h.settle(tester);
    }
  }

  /// Past the last page the next chapter is still loading; once it lands
  /// the reader shows its first page with no tap.
  Future<void> loadsIntoPageOne(WidgetTester tester) async {
    expect(find.byType(ChapterTransition), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(spokenIcon('Next'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ChapterTransition),
        matching: find.text('Ch. 3'),
      ),
      findsOneWidget,
    );
    expect(h.progress.markedRead, ['/c/2']);
    source.gate.complete(fakePages('/c/3', 2));
    await h.settle(tester);
    expect(find.byType(ChapterTransition), findsNothing);
    expect(find.widgetWithText(SnackBar, 'Ch. 3'), findsOneWidget);
    expect(h.loaded, contains('https://img.test/c/3/0.png'));
    expect(h.opened, isEmpty);
    await tester.pump(const Duration(seconds: 2));
    await h.settle(tester);
    expect(find.byType(SnackBar), findsNothing);
  }

  testWidgets('left-to-right waits on a loading page, then page 1', (
    tester,
  ) async {
    await open(tester, ReaderMode.pagedLtr);
    expect(source.pageCalls, ['/c/2'], reason: 'chapter 3 is gated');
    await press(tester, LogicalKeyboardKey.arrowRight, 4);
    await loadsIntoPageOne(tester);
    await tester.tapAt(const Offset(400, 300));
    await h.settle(tester);
    expect(find.text('1 / 2'), findsOneWidget);
  });

  testWidgets('right-to-left waits on a loading page, then page 1', (
    tester,
  ) async {
    await open(tester, ReaderMode.pagedRtl);
    await press(tester, LogicalKeyboardKey.arrowLeft, 4);
    await loadsIntoPageOne(tester);
    await tester.tapAt(const Offset(400, 300));
    await h.settle(tester);
    expect(find.text('1 / 2'), findsOneWidget);
  });

  testWidgets('webtoon waits on a loading page, then scrolls on', (
    tester,
  ) async {
    await open(tester, ReaderMode.webtoon);
    await press(tester, LogicalKeyboardKey.arrowDown, 12);
    await loadsIntoPageOne(tester);
  });

  testWidgets('the very last chapter ends on "No more chapters"', (
    tester,
  ) async {
    h = ReaderHarness(
      source: FakeSource(
        chapterList: const [ChapterInfo(url: '/c/2', name: 'Ch. 2')],
        pageMap: {'/c/2': fakePages('/c/2', 4)},
      ),
    );
    await open(tester, ReaderMode.pagedLtr);
    await press(tester, LogicalKeyboardKey.arrowRight, 4);
    expect(spokenIcon('No more chapters'), findsOneWidget);
    expect(find.text('Finished'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(ChapterTransition),
        matching: find.byType(IconButton),
      ),
      findsNothing,
    );
  });

  testWidgets('an unknown chapter list is retried, then read on', (
    tester,
  ) async {
    final flaky = _FlakyList();
    h = ReaderHarness(source: flaky);
    await open(tester, ReaderMode.pagedLtr);
    await press(tester, LogicalKeyboardKey.arrowRight, 4);
    expect(spokenIcon('Could not open'), findsOneWidget);
    expect(find.textContaining('<redacted>'), findsOneWidget);
    flaky.failures = 0;
    await tester.tap(spokenIcon('Retry'));
    await h.settle(tester);
    expect(find.byType(ChapterTransition), findsNothing);
    expect(find.widgetWithText(SnackBar, 'Ch. 3'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });
}

/// The chapter list fails until [failures] reaches zero.
class _FlakyList extends FakeSource {
  new()
    : super(
        chapterList: harnessChapters,
        pageMap: {'/c/2': fakePages('/c/2', 4), '/c/3': fakePages('/c/3', 2)},
      );

  int failures = 99;

  @override
  Future<List<ChapterInfo>> chapters(String mangaUrl) async {
    if (failures > 0) throw StateError('GET https://src.test/m?token=S -> 503');
    return chapterList;
  }
}
