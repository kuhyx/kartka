import 'dart:io';

import 'package:kartka/platform/http_client.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:kartka/plugins/runtime/host_api.dart';

export 'package:kartka/platform/memory/memory_platform.dart';

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
    if (url.contains('fail.test')) throw StateError('network down');
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
  void log(String message) => logs.add(message);

  @override
  Future<String?> prefsGet(String key) async => prefs[key];

  @override
  Future<void> prefsSet(String key, String value) async => prefs[key] = value;

  @override
  Future<Map<String, Object?>> browserLoad(
    String url, {
    Map<String, String> headers = const {},
    List<String> scripts = const [],
    String? waitFor,
    bool awaitResponse = false,
    int? timeoutMs,
  }) async => throw UnsupportedError('no browser in these tests');
}

/// Serves fixtures (the demo repo and the demo site) over the shared fake.
class FakeHttp {
  /// URL to (status, body) overrides, checked before the fixture routes.
  final Map<String, ({int status, String body})> overrides = {};

  /// When set, every request throws it.
  Exception? failWith;

  /// The client handed to code under test.
  late final FakeKartkaHttp client = FakeKartkaHttp(_handle);

  /// `METHOD url` of every request so far.
  List<String> get requested => [
    for (final r in client.requests) '${r.method} ${r.url}',
  ];

  static const _routes = <String, String>{
    'https://repo.test/index.json': 'index.json',
    'https://repo.test/demo.js': 'demo.js',
    'https://demo.test/popular?page=1': 'site/popular.html',
    'https://demo.test/latest?page=1': 'site/latest.html',
    'https://demo.test/search?q=bers%20erk&page=1': 'site/search.html',
    'https://demo.test/m/1': 'site/m1.html',
    'https://demo.test/m/1/c/1': 'site/c1.html',
  };

  KartkaResponse _handle(FakeRequest r) {
    if (failWith != null) throw failWith!;
    final o = overrides[r.url.toString()];
    if (o != null) return _resp(o.status, o.body);
    final f = _routes[r.url.toString()];
    return f == null ? _resp(404, '') : _resp(200, fixture(f));
  }

  KartkaResponse _resp(int status, String body) => FakeKartkaHttp.text(
    body,
    status: status,
    headers: const {'content-type': 'text/html'},
  );
}
