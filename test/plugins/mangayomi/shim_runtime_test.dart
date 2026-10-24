import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/plugins/runtime/host_api.dart';

import 'support.dart';

/// Runs [body] in the shim (see `probeExtension`) and decodes its result.
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

Exchange ok(String method, String url, String body) =>
    Exchange(method, url, 201, {'x': 'y'}, body);

void main() {
  test('Client.get returns Mangayomi response shape, never throws', () async {
    final h = ReplayServices([ok('GET', 'https://a.test/1', 'hi')]);
    expect(
      await run('''
const r = await new Client({a: 1}).get("https://a.test/1", {A: 2});
const h = await new Client().head("https://a.test/1");
return [r.body, r.statusCode, r.headers, r.request.url, h.body];
        ''', h),
      [
        'hi',
        201,
        {'x': 'y'},
        'https://a.test/1',
        'hi',
      ],
    );
    expect(h.sentHeaders.first, {'A': '2'});
  });

  test('Client.post encodes JSON, form and string bodies', () async {
    final h = ReplayServices([ok('POST', 'https://a.test/p', 'ok')]);
    await run('''
const c = new Client(); const u = "https://a.test/p";
await c.post(u, {"content-type": "application/json"}, {q: 1});
await c.post(u, {}, {q: "a b", n: null});
await c.post(u, undefined, "raw");
await c.post(u, {}, [1, 2]);
await c.post(u);
return 0;
      ''', h);
    expect(h.sentBodies, ['{"q":1}', 'q=a%20b&n=', 'raw', '[1,2]', '']);
    expect(h.sentHeaders[1], {
      'Content-Type': 'application/x-www-form-urlencoded',
    });
    expect(h.sentHeaders[3], isEmpty);
  });

  test('unsupported HTTP verbs throw named errors', () async {
    for (final verb in ['put', 'patch', 'delete']) {
      await expectLater(
        run('return new Client().$verb("https://a.test");', ReplayServices()),
        throwsA(
          isA<PluginException>().having((e) => e.message, 'm', contains(verb)),
        ),
      );
    }
  });

  test('SharedPreferences: defaults, stored values, setString', () async {
    const ext = '''
const mangayomiSources = [];
class DefaultExtension extends MProvider {
  getSourcePreferences() {
    return [
      {key: "l", listPreference: {valueIndex: 1, entryValues: ["a", "b"]}},
      {key: "l0", listPreference: {entryValues: ["z"]}},
      {key: "m", multiSelectListPreference: {values: ["x"]}},
      {key: "m0", multiSelectListPreference: {}},
      {key: "s", switchPreferenceCompat: {value: true}},
      {key: "c", checkBoxPreference: {}},
      {key: "e", editTextPreference: {value: "https://e.test"}},
      {key: "e0", editTextPreference: {}},
      {key: "odd", somethingElse: {}},
      {key: "raw", editTextPreference: {value: "d"}},
      null,
    ];
  }
  async getPopular(page) {
    const p = new SharedPreferences();
    const out = ["l", "l0", "m", "m0", "s", "c", "e", "e0", "odd", "raw"]
      .map((k) => p.get(k));
    out.push(p.get("none", 5), p.get("none"), p.getString("s"),
      p.getString("none", "fb"));
    p.setString("e", "https://new.test");
    out.push(p.get("e"));
    return { list: [{ name: JSON.stringify(out), link: "/x" }] };
  }
}
''';
    final h = ReplayServices()..prefs['pref:raw'] = 'not json';
    final s = sessionFor(testEntry(), ext, h);
    addTearDown(s.dispose);
    final r = await s.call(PluginMethod.popular, [1]);
    final title = (((r! as Map)['items']! as List).single as Map)['title'];
    expect(jsonDecode(title! as String), [
      'b',
      'z',
      ['x'],
      <Object?>[],
      true,
      false,
      'https://e.test',
      '',
      null,
      'not json',
      5,
      null,
      'true',
      'fb',
      'https://new.test',
    ]);
    expect(h.prefs['pref:e'], '"https://new.test"');
    // The stored value wins on the next call.
    final again = await s.call(PluginMethod.popular, [1]);
    final t2 = (((again! as Map)['items']! as List).single as Map)['title'];
    expect((jsonDecode(t2! as String) as List)[6], 'https://new.test');
  });

  test('string helpers, atob/btoa and console', () async {
    final h = ReplayServices();
    expect(
      await run('''
console.log("hello", 1);
const s = "a/b/c";
return [s.substringAfter("/"), s.substringAfterLast("/"),
s.substringBefore("/"), s.substringBeforeLast("/"),
s.substringAfter("#"), s.substringBeforeLast("#"),
s.substringAfterLast("#"), s.substringBefore("#"),
"x[1]y".substringBetween("[", "]"),
btoa("hi?"), btoa("ab"), btoa("a"), atob("aGk/"), atob("YWI=")];
        ''', h),
      [
        'b/c',
        'c',
        'a',
        'a/b',
        'a/b/c',
        'a/b/c',
        'a/b/c',
        'a/b/c',
        '1',
        'aGk/',
        'YWI=',
        'YQ==',
        'hi?',
        'ab',
      ],
    );
    expect(h.logs, contains('hello 1'));
    for (final bad in ['btoa("Ā")', 'atob("*")']) {
      await expectLater(
        run('return $bad;', h),
        throwsA(isA<PluginException>()),
      );
    }
  });
}
