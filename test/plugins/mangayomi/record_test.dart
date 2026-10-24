@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/platform/http_client.dart';
import 'package:kartka/plugins/mangayomi/mangayomi_index.dart';
import 'package:kartka/plugins/runtime/host_api.dart';

import 'support.dart';

/// Live smoke test AND fixture recorder (the only test touching the
/// network). As a smoke test it asserts every entry point answered; it
/// rewrites `http/<name>.json` only when `RECORD=1` is set, e.g.
/// `RECORD=1 fvm flutter test --run-skipped -t live test/plugins/mangayomi/record_test.dart --plain-name <name>`
/// (re-recording changes the values `extension_cases.dart` asserts).
/// Requests are spaced 2 s apart; Cloudflare challenges are recorded as-is.
const pinnedRepo =
    'https://raw.githubusercontent.com/entityJY/mangayomi-extensions-eJ/'
    'f21a60bf026dd122f9b80042e1c3d220a38aa07a';

/// Live host that records every exchange.
class RecordingServices extends ReplayServices {
  final List<Map<String, Object?>> exchanges = [];
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15);
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  Future<HostHttpResponse> _live(
    String method,
    String url,
    Map<String, String> headers,
    String? body,
  ) async {
    final wait = _last
        .add(const Duration(seconds: 2))
        .difference(DateTime.now());
    if (!wait.isNegative) await Future<void>.delayed(wait);
    _last = DateTime.now();
    final req = await _client.openUrl(method, Uri.parse(url));
    req.followRedirects = true;
    if (!headers.keys.any((k) => k.toLowerCase() == 'user-agent')) {
      req.headers.set('user-agent', kartkaUserAgent);
    }
    headers.forEach(req.headers.set);
    if (body != null) req.write(body);
    final res = await req.close().timeout(const Duration(seconds: 20));
    final text = await utf8.decodeStream(res).catchError((_) => '');
    final h = <String, String>{};
    res.headers.forEach((k, v) {
      if (k == 'content-type' || k == 'location') h[k] = v.join(', ');
    });
    exchanges.add({
      'method': method,
      'url': url,
      if (headers.isNotEmpty) 'requestHeaders': headers,
      'status': res.statusCode,
      'headers': h,
      'body': text,
    });
    return HostHttpResponse(status: res.statusCode, headers: h, body: text);
  }

  @override
  Future<HostHttpResponse> httpGet(
    String url, {
    Map<String, String> headers = const {},
  }) => _live('GET', url, headers, null);

  @override
  Future<HostHttpResponse> httpPost(
    String url, {
    Map<String, String> headers = const {},
    String? body,
  }) => _live('POST', url, headers, body);
}

Future<void> record(
  String name,
  String path,
  String query, {
  String? pagesUrl,
}) async {
  final live = RecordingServices();
  final src = await live.httpGet('$pinnedRepo/javascript/manga/src/$path');
  expect(src.status, 200);
  final entry = MangayomiIndex.parse(fixtureJson('index.json'))
      .firstWhere((e) => e.sourceCodeUrl.endsWith('/$path') && e.lang == 'en');
  final s = sessionFor(entry, src.body, live);
  final results = <String, String>{};
  Future<Object?> step(PluginMethod m, List<Object?> args) async {
    try {
      final r = await s.call(m, args);
      results[m.name] = 'ok';
      return r;
    } on PluginException catch (e) {
      results[m.name] = 'FAIL ${e.message}';
      return null;
    }
  }

  await step(PluginMethod.popular, [1]);
  await step(PluginMethod.latest, [1]);
  final found = await step(PluginMethod.search, [query, 1]) as Map?;
  final items = (found?['items'] as List?) ?? const [];
  // The first search hit that has chapters (a listed series can be empty).
  Object? url;
  for (final item in items.take(3)) {
    url = (item as Map)['url'];
    await step(PluginMethod.details, [url]);
    final ch = await step(PluginMethod.chapters, [url]) as List?;
    if (ch != null && ch.isNotEmpty) {
      await step(PluginMethod.pages, [(ch.last as Map)['url']]);
      break;
    }
  }
  // Chapter list broken upstream: still exercise pages on a known chapter.
  if (results['pages'] == null && pagesUrl != null) {
    await step(PluginMethod.pages, [pagesUrl]);
  }
  await s.dispose();
  final out = {
    'recordedAt': DateTime.now().toUtc().toIso8601String(),
    'firstItem': url,
    'query': query,
    'liveResults': results,
    'entry': entry.raw,
    'exchanges': live.exchanges,
  };
  if (Platform.environment['RECORD'] == '1') {
    File('$fixtureDir/http/$name.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(const JsonEncoder.withIndent(' ').convert(out));
  }
  // The recorder's job is to report live results to the person re-recording.
  // ignore: avoid_print
  print('$name: $results');
  expect(results.values, everyElement('ok'));
}

void main() {
  test('weebcentral', () => record('weebcentral', 'en/weebcentral.js', 'solo'));
  test(
    'webtoons',
    () => record(
      'webtoons',
      'all/webtoons.js',
      'tower',
      pagesUrl:
          'https://www.webtoons.com/en/action/a-wimps-tower-strategy-guide/'
          'episode-1/viewer?title_no=9701&episode_no=1',
    ),
  );
  test('mangadex', () => record('mangadex', 'all/mangadex.js', 'berserk'));
}
