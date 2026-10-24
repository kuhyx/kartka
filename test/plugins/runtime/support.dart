import 'dart:io';

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
