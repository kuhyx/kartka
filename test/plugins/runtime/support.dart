import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:kartka/platform/http_client.dart';
import 'package:kartka/platform/key_value_store.dart';
import 'package:kartka/plugins/runtime/host_api.dart';
import 'package:kartka/plugins/runtime/html_select.dart';

const fixtureDir = 'test/fixtures/plugins';

String fixture(String name) => File('$fixtureDir/$name').readAsStringSync();

/// Host services for tests: serves the recorded demo site, no network.
class FakeServices implements PluginHostServices {
  final List<String> logs = [];
  final Map<String, String> prefs = {};
  final List<String> requested = [];
  Duration? delay;

  static const _routes = <String, String>{
    'https://demo.test/popular?page=1': 'site/popular.html',
    'https://demo.test/latest?page=1': 'site/latest.html',
    'https://demo.test/search?q=bers%20erk&page=1': 'site/search.html',
    'https://demo.test/m/1': 'site/m1.html',
    'https://demo.test/m/1/c/1': 'site/c1.html',
  };

  @override
  Future<HostHttpResponse> httpGet(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    requested.add(url);
    if (delay != null) await Future<void>.delayed(delay!);
    final f = _routes[url];
    if (f == null) {
      return const HostHttpResponse(status: 404, headers: {}, body: '');
    }
    return HostHttpResponse(status: 200, headers: {}, body: fixture(f));
  }

  @override
  Future<HostHttpResponse> httpPost(
    String url, {
    Map<String, String> headers = const {},
    String? body,
  }) => httpGet(url, headers: headers);

  @override
  List<HtmlMatch> htmlSelect(String html, String css) => selectHtml(html, css);

  @override
  void log(String message) => logs.add(message);

  @override
  Future<String?> prefsGet(String key) async => prefs[key];

  @override
  Future<void> prefsSet(String key, String value) async => prefs[key] = value;
}

/// In-memory [KeyValueStore].
class MemoryKv implements KeyValueStore {
  final Map<String, String> data = {};

  @override
  Future<String?> get(String key) async => data[key];

  @override
  Future<void> set(String key, String value) async => data[key] = value;

  @override
  Future<void> remove(String key) async => data.remove(key);

  @override
  Future<Map<String, String>> entries({String prefix = ''}) async => {
    for (final e in data.entries)
      if (e.key.startsWith(prefix)) e.key: e.value,
  };
}

/// [KartkaHttp] serving fixtures: the demo repo and the demo site.
class FakeHttp extends KartkaHttp {
  /// URL to (status, body) overrides, checked before the fixture routes.
  final Map<String, ({int status, String body})> overrides = {};
  final List<String> requested = [];
  Object? failWith;

  static const _routes = <String, String>{
    'https://repo.test/index.json': 'index.json',
    'https://repo.test/demo.js': 'demo.js',
    'https://demo.test/popular?page=1': 'site/popular.html',
    'https://demo.test/latest?page=1': 'site/latest.html',
    'https://demo.test/search?q=bers%20erk&page=1': 'site/search.html',
    'https://demo.test/m/1': 'site/m1.html',
    'https://demo.test/m/1/c/1': 'site/c1.html',
  };

  @override
  Future<KartkaResponse> send(
    String method,
    Uri url, {
    Map<String, String> headers = const {},
    String? body,
  }) async {
    requested.add('$method $url');
    if (failWith != null) throw failWith!;
    final o = overrides[url.toString()];
    if (o != null) return _resp(o.status, o.body);
    final f = _routes[url.toString()];
    return f == null ? _resp(404, '') : _resp(200, fixture(f));
  }

  KartkaResponse _resp(int status, String body) => KartkaResponse(
    statusCode: status,
    bodyBytes: Uint8List.fromList(utf8.encode(body)),
    headers: const {'content-type': 'text/html'},
  );
}
