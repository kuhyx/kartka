import 'package:flutter_test/flutter_test.dart';
import 'package:js_interpreter/js_interpreter.dart';
import 'package:kartka/plugins/runtime/worker_script.dart';

/// Runs the generated worker script against a fake worker scope (the real
/// Worker glue is web-only), proving the lockdown and handshake.
void main() {
  late JSInterpreter js;
  late List<String> posted;

  void boot(String plugin) {
    posted = [];
    js = JSInterpreter()
      ..setGlobal('__post', (dynamic m) {
        posted.add('$m');
        return null;
      })
      ..eval('''
var self = globalThis;
self.postMessage = function (m) { __post(m); };
self.fetch = function () { return 'net'; };
self.XMLHttpRequest = function () {};
''')
      ..eval(buildWorkerScript(plugin));
  }

  test('posts ready after the plugin evaluates', () {
    boot(
      'function popular(p) { return [typeof fetch, typeof importScripts]; }',
    );
    expect(posted, ['{"t":"ready"}']);
  });

  test('removes network globals before plugin code runs', () {
    boot(
      'var seen = [typeof fetch, typeof XMLHttpRequest, typeof postMessage];',
    );
    expect(js.evalToDart('seen.join()'), 'undefined,undefined,undefined');
  });

  test('routes onmessage into the prelude and answers calls', () {
    boot('function popular(p) { return p + 1; }');
    posted.clear();
    js
      ..eval(
        'self.onmessage({data: JSON.stringify('
        '{t:"call", id:1, method:"popular", args:[41]})})',
      )
      ..runPendingAsyncTasks();
    expect(posted.single, '{"t":"result","id":1,"ok":true,"value":42}');
  });

  test('a throwing plugin reports fail instead of ready', () {
    boot('throw new Error("bad plugin");');
    expect(posted.single, contains('"fail"'));
    expect(posted.single, contains('bad plugin'));
  });
}
