import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/plugins/runtime/plugin_index.dart';

import 'support.dart';

void main() {
  final base = Uri.parse('https://repo.test/index.json');
  const manifest =
      '"id":"a","name":"A","version":"1","lang":"en","baseUrl":"https://a",'
      '"apiVersion":1';
  String index(String extra) => '{"plugins":[{$manifest,$extra}]}';

  test('parses the fixture index and resolves relative urls', () {
    final e = parsePluginIndex(fixture('index.json'), base);
    expect(e.map((x) => x.manifest.id), ['demo', 'nohash']);
    expect(e.first.url.toString(), 'https://repo.test/demo.js');
    expect(e.first.sha256, hasLength(64));
    expect(e.last.sha256, isNull);
    expect(e.first.repoUrl, base.toString());
  });

  test('lowercases the digest and accepts absolute urls', () {
    final h = 'AB' * 32;
    final e = parsePluginIndex(
      index('"url":"https://cdn.test/a.js","sha256":"$h"'),
      base,
    );
    expect(e.single.sha256, h.toLowerCase());
    expect(e.single.url.host, 'cdn.test');
  });

  test('rejects malformed indexes with a readable reason', () {
    void bad(String body, String text) => expect(
      () => parsePluginIndex(body, base),
      throwsA(
        isA<FormatException>().having((e) => e.message, 'm', contains(text)),
      ),
    );
    bad('nope', 'not JSON');
    bad('{}', 'no "plugins"');
    bad('{"plugins":[3]}', 'plugin #0: not an object');
    bad(index('"x":1'), 'missing "url"');
    bad(index('"url":"ftp://x/a.js"'), 'must be http');
    bad(index('"url":"a.js","sha256":"abc"'), 'sha256');
    bad(index('"url":"a.js","sha256":5'), 'sha256');
    bad('{"plugins":[{"id":"a"}]}', 'plugin #0');
  });

  test('isNewerVersion compares dotted numbers', () {
    expect(isNewerVersion('1.0.1', '1.0.0'), true);
    expect(isNewerVersion('1.0', '1.0.0'), false);
    expect(isNewerVersion('1.0.0', '1.0.1'), false);
    expect(isNewerVersion('2', '1.9.9'), true);
    expect(isNewerVersion('1.0.0', '1.0.0'), false);
    expect(isNewerVersion('1.0.0-b', '1.0.0'), true);
  });
}
