import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/plugins/runtime/host_api.dart';

import 'support.dart';

/// Runs [body] in the shim and decodes the JSON it returns as a title.
Future<Object?> run(String body, ReplayServices services) async {
  final s = sessionFor(testEntry(), probeExtension(body), services);
  try {
    final r = await s.call(PluginMethod.popular, [1]);
    final item = ((r! as Map)['items']! as List).single as Map;
    return jsonDecode(item['title']! as String);
  } finally {
    await s.dispose();
  }
}

void main() {
  test(
    'evaluateJavascriptViaWebview resolves to the setResponse string',
    () async {
      final h = ReplayServices()
        ..onBrowser = (url, o) async => {
          'url': url,
          'html': '<p/>',
          'response': 'token-42',
          'timedOut': false,
        };
      expect(
        await run('''
return await evaluateJavascriptViaWebview("https://site.test/x",
  {Referer: "https://site.test/", N: 1},
  ["window.flutter_inappwebview.callHandler('setResponse', 'token-42')"], 8);
''', h),
        'token-42',
      );
      final (url, o) = h.browserCalls.single;
      expect(url, 'https://site.test/x');
      expect(o['headers'], {'Referer': 'https://site.test/', 'N': '1'});
      expect(o['scripts'], [
        "window.flutter_inappwebview.callHandler('setResponse', 'token-42')",
      ]);
      expect(o['awaitResponse'], isTrue);
      expect(o['timeoutMs'], 8000);
    },
  );

  test('a timeout resolves to the empty string; time is clamped', () async {
    final h = ReplayServices()
      ..onBrowser = (url, o) async => {
        'url': url,
        'html': '',
        'response': null,
        'timedOut': true,
      };
    expect(
      await run('''
const a = await evaluateJavascriptViaWebview("https://site.test/x");
const b = await evaluateJavascriptViaWebview("https://site.test/y", null, "no", 300);
const c = await evaluateJavascriptViaWebview("https://site.test/z", {}, [], -1);
return [a, b, c];
''', h),
      ['', '', ''],
    );
    expect(h.browserCalls.map((c) => c.$2['timeoutMs']), [25000, 25000, 25000]);
    expect(h.browserCalls[1].$2['scripts'], isEmpty);
    expect(h.browserCalls[1].$2['headers'], isEmpty);
  });
}
