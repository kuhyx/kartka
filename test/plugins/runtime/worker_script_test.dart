import 'dart:convert';

import 'package:flutter_js/flutter_js.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/plugins/runtime/worker_script.dart';

/// Runs the generated worker script against a fake worker scope (the real
/// Worker and iframe glue is web-only), proving the lockdown and handshake.
void main() {
  late QuickJsRuntime2 rt;
  late List<String> posted;

  void boot(String plugin) {
    posted = [];
    rt = QuickJsRuntime2()
      ..onMessage('post', (dynamic m) => posted.add(m as String));
    for (final code in [
      '''
var self = globalThis;
self.fetch = function () { return 'net'; };
self.XMLHttpRequest = function () {};
self.postMessage = function () {};
var port = { postMessage: function (m) { sendMessage('post', JSON.stringify(m)); } };
''',
      buildWorkerScript(plugin),
      'self.onmessage({ data: { port: port } });',
    ]) {
      final r = rt.evaluate(code);
      expect(r.isError, false, reason: r.stringResult);
    }
  }

  tearDown(() => rt.dispose());

  test('posts ready on the port once the plugin evaluates', () {
    boot('function popular(p) { return 1; }');
    expect(posted, ['{"t":"ready"}']);
  });

  test('removes network globals before plugin code runs', () {
    boot(
      'var seen = [typeof fetch, typeof XMLHttpRequest, typeof postMessage];',
    );
    expect(
      rt.evaluate('seen.join()').stringResult,
      'undefined,undefined,undefined',
    );
  });

  test('routes port messages into the prelude and answers calls', () {
    boot('function popular(p) { return p + 1; }');
    posted.clear();
    final call = jsonEncode({
      't': 'call',
      'id': 1,
      'method': 'popular',
      'args': [41],
    });
    rt
      ..evaluate('port.onmessage({ data: ${jsonEncode(call)} })')
      ..executePendingJob();
    expect(posted.single, '{"t":"result","id":1,"ok":true,"value":42}');
  });

  test('a throwing plugin reports fail instead of ready', () {
    boot('throw new Error("bad plugin");');
    expect(posted.single, contains('"fail"'));
    expect(posted.single, contains('bad plugin'));
  });

  test('the host page is sandbox-safe: CSP, escaped script ends', () {
    final page = buildHostPage('var x = "</script><!-- evil";');
    expect(page, contains("connect-src 'none'"));
    expect(page, contains('worker-src blob:'));
    expect('</script>'.allMatches(page), hasLength(1));
    expect(page, isNot(contains('<!-- evil')));
  });
}
