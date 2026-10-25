import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/reader/logic/reader_mode.dart';
import 'package:kartka/reader/ui/page_slider.dart';
import 'package:kartka/reader/ui/webtoon_reader_view.dart';

import '../support/fakes.dart';
import 'reader_harness.dart';

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

  testWidgets('opens on page 1, keeps the screen awake, prefetches', (
    tester,
  ) async {
    await ltr(tester);
    expect(find.byType(Image), findsWidgets);
    expect(h.system.awake, [true]);
    expect(h.loaded.first, 'https://img.test/c/2/0.png');
    expect(h.loaded, hasLength(4));
    await tester.pumpWidget(const SizedBox());
    expect(h.system.awake, [true, false]);
  });

  testWidgets('tap zones: centre toggles the menu, right goes forward', (
    tester,
  ) async {
    await ltr(tester);
    expect(find.byType(PageSlider), findsNothing);
    await tester.tapAt(const Offset(400, 300));
    await h.settle(tester);
    expect(find.text('1 / 4'), findsOneWidget);
    expect(find.text('Ch. 2'), findsOneWidget);
    await tester.tapAt(const Offset(780, 300));
    await h.settle(tester);
    expect(find.text('2 / 4'), findsOneWidget);
    await tester.tapAt(const Offset(10, 300));
    await h.settle(tester);
    expect(find.text('1 / 4'), findsOneWidget);
  });

  testWidgets('keyboard: arrows, fullscreen and Escape', (tester) async {
    await ltr(tester);
    await key(tester, LogicalKeyboardKey.arrowRight);
    await key(tester, LogicalKeyboardKey.pageDown);
    await tester.tapAt(const Offset(400, 300));
    await h.settle(tester);
    expect(find.text('3 / 4'), findsOneWidget);
    await key(tester, LogicalKeyboardKey.keyF);
    await key(tester, LogicalKeyboardKey.keyF);
    expect(h.system.fullscreen, [true, false]);
    await key(tester, LogicalKeyboardKey.escape);
    expect(h.exits, 1);
  });

  testWidgets('slider and chapter buttons navigate', (tester) async {
    await ltr(tester);
    await tester.tapAt(const Offset(400, 300));
    await h.settle(tester);
    tester.widget<PageSlider>(find.byType(PageSlider)).onChanged(3);
    await h.settle(tester);
    expect(find.text('4 / 4'), findsOneWidget);
    await tester.tap(find.byTooltip('Next chapter'));
    await tester.tap(find.byTooltip('Previous chapter'));
    expect(h.opened, ['/c/3', '/c/1']);
    await tester.tap(find.byTooltip('Back'));
    expect(h.exits, 1);
    await tester.tap(find.byTooltip('Fullscreen'));
    expect(h.system.fullscreen, [true]);
  });

  testWidgets('switching to webtoon persists per manga', (tester) async {
    await ltr(tester);
    await tester.tapAt(const Offset(400, 300));
    await h.settle(tester);
    await tester.tap(find.byTooltip('Reading mode'));
    await h.settle(tester);
    await tester.tap(find.text(ReaderMode.webtoon.label).last);
    await h.settle(tester);
    expect(find.byType(WebtoonReaderView), findsOneWidget);
    expect(await h.prefs.modeFor('fake|/m/1'), ReaderMode.webtoon);
  });

  testWidgets('a failed load explains and offers retry and back', (
    tester,
  ) async {
    h = ReaderHarness(source: FakeSource(chapterList: harnessChapters));
    await h.pump(tester);
    expect(find.textContaining('no pages'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await h.settle(tester);
    expect(h.source.pageCalls, ['/c/2', '/c/2']);
    await tester.tap(find.text('Back'));
    expect(h.exits, 1);
  });

  testWidgets('the settings sheet edits global settings', (tester) async {
    await ltr(tester);
    await tester.tapAt(const Offset(400, 300));
    await h.settle(tester);
    await tester.tap(find.byTooltip('Reader settings'));
    await h.settle(tester);
    await tester.tap(find.text('Invert tap zones'));
    await h.settle(tester);
    expect((await h.prefs.settings()).invertTaps, isTrue);
  });

  testWidgets('webtoon scrolls back into the previous chapter at its end', (
    tester,
  ) async {
    await h.prefs.setModeFor('fake|/m/1', ReaderMode.webtoon);
    await h.pump(tester);
    await key(tester, LogicalKeyboardKey.arrowUp);
    await key(tester, LogicalKeyboardKey.arrowUp);
    expect(h.openedAtEnd, ['/c/1']);
  });

  testWidgets('fullscreen follows the state the platform reports', (
    tester,
  ) async {
    await ltr(tester);
    h.system.reported = true;
    await key(tester, LogicalKeyboardKey.keyF);
    h.system.reported = false;
    await key(tester, LogicalKeyboardKey.keyF);
    expect(h.system.fullscreen, [false, true]);
  });
}
