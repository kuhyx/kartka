import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/platform/browser_engine.dart';
import 'package:kartka/platform/engine_scripts.dart';
import 'package:kartka/platform/memory/memory_platform.dart';

void main() {
  final url = Uri.parse('https://site.test/');

  test('UnavailableBrowser refuses every engine call', () async {
    const b = UnavailableBrowser();
    expect(b.inApp, isFalse);
    await expectLater(
      b.load(EngineRequest(url: url)),
      throwsA(isA<EngineUnavailable>()),
    );
    await expectLater(b.openExternal(url), throwsA(isA<EngineUnavailable>()));
    await expectLater(b.finish(url), throwsA(isA<EngineUnavailable>()));
    expect(b.buildView(url), isA<SizedBox>());
    const child = Text('x');
    expect(identical(b.host(child), child), isTrue);
    expect('${const EngineUnavailable('no-browser')}', contains('no-browser'));
  });

  test('memoryPlatform defaults to an unavailable browser', () {
    expect(memoryPlatform().browser, isA<UnavailableBrowser>());
    final fake = FakeBrowser();
    expect(memoryPlatform(browser: fake).browser, same(fake));
  });

  test('FakeBrowser answers loads and records the interactive flow', () async {
    final fake = FakeBrowser(
      onLoad: (r) async => EngineResult(url: r.url, html: '<p>${r.url}</p>'),
    );
    final r = await fake.load(EngineRequest(url: url));
    expect(r.html, '<p>$url</p>');
    expect(fake.loads.single.url, url);
    await fake.openExternal(url);
    await fake.finish(url);
    expect(fake.opened, [url]);
    expect(fake.finished, [url]);
    expect(fake.buildView(url), isA<Placeholder>());
    expect(FakeBrowser(inApp: true).inApp, isTrue);
    expect((await FakeBrowser().load(EngineRequest(url: url))).html, isEmpty);
  });

  test('decodeEngineValue unwraps one or two JSON layers', () {
    expect(decodeEngineValue('{"a":1}'), {'a': 1});
    expect(decodeEngineValue(r'"{\"a\":1}"'), {'a': 1});
    expect(decodeEngineValue('plain'), 'plain');
    expect(decodeEngineValue(null), isNull);
    expect(decodeEngineValue(3), 3);
    expect(decodeEngineValue('"plain"'), 'plain');
  });

  test('results serialise for plugins; fakes pass the app through', () {
    final r = EngineResult(
      url: url,
      html: '<p/>',
      resources: const ['https://site.test/a.jpg'],
      status: 200,
      response: 'ok',
      timedOut: true,
    );
    expect(r.toJson(), {
      'url': '$url',
      'status': 200,
      'html': '<p/>',
      'resources': ['https://site.test/a.jpg'],
      'response': 'ok',
      'timedOut': true,
    });
    const child = Text('app');
    expect(identical(FakeBrowser().host(child), child), isTrue);
    // A runtime (non-const) instance, so the constructor line is covered.
    // ignore: prefer_const_constructors
    expect(UnavailableBrowser().inApp, isFalse);
  });

  test('the probe embeds the selector safely', () {
    final js = engineProbeJs('a[href="x"]');
    expect(js.startsWith(kEngineProbeMarker), isTrue);
    expect(js, contains(r'"a[href=\"x\"]"'));
    expect(engineProbeJs(null), contains('null'));
  });
}
