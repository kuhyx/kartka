import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kartka/platform/browser_engine.dart';
import 'package:kartka/platform/engine_scripts.dart';
import 'package:kartka/platform/wrapper_browser.dart';

/// A stand-in for the wrapper's /engine routes over one fake page.
class FakeEngineRoutes {
  final log = <String>[];
  int status = 200;
  String error = 'no-browser';
  bool ran = false;

  late final client = MockClient((r) async {
    expect(r.headers['x-kartka'], '1');
    final path = r.url.path;
    final body = r.body.isEmpty ? null : jsonDecode(r.body) as Map;
    log.add('${r.method} $path');
    if (status != 200) {
      return http.Response(jsonEncode({'error': error}), status);
    }
    if (path == '/engine/page') return http.Response('{"id":"p1"}', 200);
    if (path.endsWith('/evaluate')) {
      final js = body!['expression'] as String;
      Object? value;
      if (js.startsWith(kEngineProbeMarker)) {
        value = jsonEncode({
          'ready': 'complete',
          'ran': ran,
          'matched': true,
          'href': 'https://site.test/c',
        });
      } else if (js == kEngineHookJs) {
        ran = true;
      } else if (js == kEngineSnapshotJs) {
        value = jsonEncode({
          'html': '<img src="p1.jpg">',
          'resources': ['https://site.test/p1.jpg'],
          'status': 200,
          'href': 'https://site.test/c',
        });
      }
      return http.Response(jsonEncode({'value': value}), 200);
    }
    if (r.method == 'POST' && path.endsWith('/navigate')) {
      expect(body!['headers'], {'Referer': 'https://site.test/'});
    }
    return http.Response('', path == '/engine/open' ? 202 : 204);
  });
}

void main() {
  final base = Uri.parse('http://127.0.0.1:47391/');
  final url = Uri.parse('https://site.test/c');
  late FakeEngineRoutes w;
  late WrapperBrowser b;

  setUp(() {
    w = FakeEngineRoutes();
    b = WrapperBrowser(w.client, base, pollInterval: Duration.zero);
  });

  test('loads run the shared loop over the wrapper routes', () async {
    final r = await b.load(
      EngineRequest(url: url, headers: const {'Referer': 'https://site.test/'}),
    );
    expect(r.html, '<img src="p1.jpg">');
    expect(r.resources, ['https://site.test/p1.jpg']);
    expect(w.log.first, 'POST /engine/page');
    expect(w.log[1], 'POST /engine/page/p1/navigate');
    expect(w.log.last, 'DELETE /engine/page/p1');
  });

  test('open and finish post the URL; nothing is in-app', () async {
    await b.openExternal(url);
    await b.finish(url);
    expect(w.log, ['POST /engine/open', 'POST /engine/finish']);
    expect(b.inApp, isFalse);
    expect(b.buildView(url), isA<SizedBox>());
    const child = Text('app');
    expect(identical(b.host(child), child), isTrue);
  });

  test('503 and 409 mean unavailable; other errors fail', () async {
    w.status = 503;
    await expectLater(
      b.load(EngineRequest(url: url)),
      throwsA(
        isA<EngineUnavailable>().having((e) => e.reason, 'r', 'no-browser'),
      ),
    );
    w
      ..status = 409
      ..error = 'headless-only';
    await expectLater(
      b.openExternal(url),
      throwsA(
        isA<EngineUnavailable>().having((e) => e.reason, 'r', 'headless-only'),
      ),
    );
    w.status = 500;
    await expectLater(b.finish(url), throwsStateError);
  });

  test('a failed close is ignored', () async {
    final failing = MockClient((r) async {
      if (r.method == 'DELETE') return http.Response('', 500);
      if (r.url.path == '/engine/page') return http.Response('{"id":"p"}', 200);
      if (r.url.path.endsWith('/navigate')) return http.Response('', 502);
      return http.Response('{"value":null}', 200);
    });
    final b2 = WrapperBrowser(failing, base, pollInterval: Duration.zero);
    await expectLater(b2.load(EngineRequest(url: url)), throwsStateError);
  });
}
