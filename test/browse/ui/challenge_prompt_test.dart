import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/app/routes.dart';
import 'package:kartka/browse/browse_routes.dart';
import 'package:kartka/platform/browser_engine.dart';
import 'package:kartka/platform/memory/memory_platform.dart';

import '../fakes.dart';
import 'harness.dart';

final Uri _wall = Uri.parse('https://wall.test/c/1');

void main() {
  testWidgets('a challenge offers Open in WebView, then retries (desktop)', (
    t,
  ) async {
    final src = FakeSource('wall', pageCount: 1)
      ..challenge = ChallengeRequired(_wall, 'cloudflare');
    final browser = FakeBrowser();
    final h = Harness(sources: [src], browser: browser);
    await h.pump(t, const SizedBox(), at: sourceRoute('wall'));
    expect(find.bySemanticsLabel('Browser check: cloudflare'), findsOneWidget);
    expect(find.text('wall.test'), findsOneWidget);
    expect(find.bySemanticsLabel('Could not load'), findsNothing);
    src.challenge = null;
    await t.tap(find.bySemanticsLabel('Open in WebView'));
    await t.pumpAndSettle();
    expect(browser.opened, [_wall]);
    expect(find.bySemanticsLabel('Finish in the browser window'), findsOne);
    await t.tap(find.bySemanticsLabel('Done'));
    await t.pumpAndSettle();
    expect(browser.finished, [_wall]);
    expect(find.text('Title 0'), findsOneWidget);
  });

  testWidgets('in-app: the WebView page, then retry (Android)', (t) async {
    final src = FakeSource('wall')
      ..challenge = ChallengeRequired(_wall, 'captcha');
    final browser = FakeBrowser(inApp: true);
    final h = Harness(sources: [src], browser: browser);
    await h.pump(t, const SizedBox(), at: mangaRoute('wall', '/m/1'));
    expect(find.bySemanticsLabel('Browser check: captcha'), findsOneWidget);
    src.challenge = null;
    await t.tap(find.bySemanticsLabel('Open in WebView'));
    await t.pumpAndSettle();
    expect(find.byType(Placeholder), findsOneWidget);
    expect(find.text('wall.test'), findsOneWidget);
    await t.tap(find.bySemanticsLabel('Done'));
    await t.pumpAndSettle();
    expect(browser.finished, [_wall]);
    expect(browser.opened, isEmpty);
    expect(find.text('Detail title'), findsOneWidget);
  });

  testWidgets('no engine: a snackbar, no retry', (t) async {
    final src = FakeSource('wall')
      ..challenge = ChallengeRequired(_wall, 'cloudflare');
    final h = Harness(sources: [src]);
    await h.pump(t, const SizedBox(), at: sourceRoute('wall'));
    final before = src.calls.length;
    await t.tap(find.bySemanticsLabel('Open in WebView'));
    await t.pumpAndSettle();
    expect(
      find.bySemanticsLabel(RegExp('^Browser engine unavailable')),
      findsOneWidget,
    );
    expect(src.calls.length, before);
  });

  testWidgets('a source with a site gets the AppBar action', (t) async {
    final browser = FakeBrowser();
    final h = Harness(
      sources: [FakeWebSource('site'), FakeSource('plain')],
      browser: browser,
    );
    await h.pump(t, const SizedBox(), at: sourceRoute('plain'));
    expect(find.bySemanticsLabel('Open in WebView'), findsNothing);
    final router = await h.pump(t, const SizedBox(), at: sourceRoute('site'));
    await t.tap(find.bySemanticsLabel('Open in WebView'));
    await t.pumpAndSettle();
    await t.tap(find.bySemanticsLabel('Done'));
    await t.pumpAndSettle();
    expect(browser.finished, [Uri.parse('https://site.test/')]);
    router.dispose();
  });

  test('the platform default has no engine', () {
    expect(memoryPlatform().browser.inApp, isFalse);
  });
}
