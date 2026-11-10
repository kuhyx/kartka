import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/reader/logic/reader_mode.dart';
import 'package:kartka/reader/ui/chapter_transition.dart';

import '../../helpers/spoken_icon.dart';
import '../support/fakes.dart';
import 'reader_harness.dart';

/// Chapter 2 (4 pages) followed by chapter 3 (2 pages).
FakeSource _threeChapters() => FakeSource(
  chapterList: harnessChapters,
  pageMap: {'/c/2': fakePages('/c/2', 4), '/c/3': fakePages('/c/3', 2)},
);

/// Chapter 3 fails with a secret in its URL until [fail] is cleared.
class _FlakyNext extends FakeSource {
  new()
    : super(
        chapterList: harnessChapters,
        pageMap: {'/c/2': fakePages('/c/2', 4), '/c/3': fakePages('/c/3', 2)},
      );

  bool fail = true;

  @override
  Future<List<PageRef>> pages(String chapterUrl) async {
    if (chapterUrl == '/c/3' && fail) {
      throw StateError('GET https://src.test/c/3?token=SECRET -> 500');
    }
    return await super.pages(chapterUrl);
  }
}

void main() {
  late ReaderHarness h;

  setUp(() {
    h = ReaderHarness();
  });

  Future<void> ltr(WidgetTester tester) async {
    await h.prefs.setModeFor('fake|/m/1', ReaderMode.pagedLtr);
    await h.pump(tester);
  }

  Future<void> key(WidgetTester tester, LogicalKeyboardKey k) async {
    await tester.sendKeyEvent(k);
    await h.settle(tester);
  }

  testWidgets('the last page marks read; one more lands on the next chapter', (
    tester,
  ) async {
    h = ReaderHarness(source: _threeChapters());
    await ltr(tester);
    await key(tester, LogicalKeyboardKey.arrowRight);
    expect(h.progress.recorded.map((p) => p.page), [1]);
    for (var i = 0; i < 3; i++) {
      await key(tester, LogicalKeyboardKey.arrowRight);
    }
    expect(h.progress.markedRead, ['/c/2']);
    expect(find.byType(ChapterTransition), findsNothing);
    expect(find.text('Finished'), findsNothing);
    expect(find.text('Ch. 3'), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(h.loaded, contains('https://img.test/c/3/0.png'));
    expect(h.opened, isEmpty);
    await tester.pump(const Duration(seconds: 2));
    await h.settle(tester);
    expect(find.byType(SnackBar), findsNothing);
    await tester.tapAt(const Offset(400, 300));
    await h.settle(tester);
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.text('Ch. 3'), findsOneWidget);
    await key(tester, LogicalKeyboardKey.arrowLeft);
    expect(find.text('4 / 4'), findsOneWidget);
    expect(find.text('Ch. 2'), findsWidgets);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('a failed next chapter shows the redacted error and retries', (
    tester,
  ) async {
    final source = _FlakyNext();
    h = ReaderHarness(source: source);
    await ltr(tester);
    for (var i = 0; i < 4; i++) {
      await key(tester, LogicalKeyboardKey.arrowRight);
    }
    expect(spokenIcon('Could not open'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ChapterTransition),
        matching: find.text('Ch. 3'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('https://src.test/c/3?<redacted>'), findsOne);
    expect(find.textContaining('SECRET'), findsNothing);
    final logged = await tester.runAsync(h.diagnostics.entries);
    // Once from the load on open, once from the retry on reaching the end.
    expect(logged!.map((e) => e.chapterUrl), ['/c/3', '/c/3']);
    source.fail = false;
    await tester.tap(spokenIcon('Retry'));
    await h.settle(tester);
    expect(spokenIcon('Could not open'), findsNothing);
    expect(find.byType(SnackBar), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('the last chapter ends on "No more chapters"', (tester) async {
    h = ReaderHarness(
      source: FakeSource(
        chapterList: const [ChapterInfo(url: '/c/2', name: 'Ch. 2')],
        pageMap: {'/c/2': fakePages('/c/2', 4)},
      ),
    );
    await ltr(tester);
    for (var i = 0; i < 4; i++) {
      await key(tester, LogicalKeyboardKey.arrowRight);
    }
    expect(spokenIcon('No more chapters'), findsOneWidget);
    await key(tester, LogicalKeyboardKey.arrowLeft);
    await key(tester, LogicalKeyboardKey.arrowLeft);
    for (var i = 0; i < 3; i++) {
      await key(tester, LogicalKeyboardKey.arrowLeft);
    }
    expect(spokenIcon('Start of, no previous chapter'), findsOneWidget);
    expect(h.opened, isEmpty);
  });

  testWidgets('going back past page 1 opens the previous chapter at its end', (
    tester,
  ) async {
    await ltr(tester);
    await key(tester, LogicalKeyboardKey.arrowLeft);
    await key(tester, LogicalKeyboardKey.arrowLeft);
    expect(h.opened, ['/c/1']);
    expect(h.openedAtEnd, ['/c/1']);
  });

  testWidgets('webtoon scrolls on into the next chapter', (tester) async {
    h = ReaderHarness(source: _threeChapters());
    await h.prefs.setModeFor('fake|/m/1', ReaderMode.webtoon);
    await h.pump(tester);
    for (var i = 0; i < 12 && find.byType(SnackBar).evaluate().isEmpty; i++) {
      await key(tester, LogicalKeyboardKey.arrowDown);
    }
    expect(find.widgetWithText(SnackBar, 'Ch. 3'), findsOneWidget);
    expect(h.progress.markedRead, ['/c/2']);
    expect(h.opened, isEmpty);
    await tester.pump(const Duration(seconds: 2));
  });
}
