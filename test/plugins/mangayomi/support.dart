import 'dart:convert';
import 'dart:io';

import 'package:kartka/plugins/mangayomi/mangayomi_converter.dart';
import 'package:kartka/plugins/mangayomi/mangayomi_entry.dart';
import 'package:kartka/plugins/runtime/engine.dart';
import 'package:kartka/plugins/runtime/engine_interpreter.dart';
import 'package:kartka/plugins/runtime/host_api.dart';
import 'package:kartka/plugins/runtime/html_select.dart';
import 'package:kartka/plugins/runtime/plugin_session.dart';

const fixtureDir = 'test/fixtures/mangayomi';

/// Decoded JSON fixture.
Object? fixtureJson(String name) =>
    jsonDecode(File('$fixtureDir/$name').readAsStringSync());

/// A recorded request/response pair.
class Exchange {
  Exchange(this.method, this.url, this.status, this.headers, this.body);

  factory Exchange.fromJson(Map<String, Object?> j) => Exchange(
    j['method']! as String,
    j['url']! as String,
    j['status']! as int,
    (j['headers'] as Map? ?? const {}).cast<String, String>(),
    j['body']! as String,
  );

  final String method;
  final String url;
  final int status;
  final Map<String, String> headers;
  final String body;
}

/// Loads `http/<name>.json`: `{entry, exchanges: [...]}`.
({MangayomiEntry entry, List<Exchange> exchanges}) recording(String name) {
  final j = fixtureJson('http/$name.json')! as Map<String, Object?>;
  return (
    entry: MangayomiEntry.fromJson(
      (j['entry']! as Map).cast<String, Object?>(),
    ),
    exchanges: [
      for (final e in j['exchanges']! as List)
        Exchange.fromJson((e as Map).cast<String, Object?>()),
    ],
  );
}

/// Host services replaying recorded exchanges. An unrecorded request fails
/// loudly (the plugin sees a rejected promise naming the URL).
class ReplayServices implements PluginHostServices {
  ReplayServices([List<Exchange> exchanges = const []])
    : _byKey = {for (final e in exchanges) '${e.method} ${e.url}': e};

  final Map<String, Exchange> _byKey;
  final Map<String, Exchange> routes = {};
  final List<String> requested = [];
  final List<Map<String, String>> sentHeaders = [];
  final List<String?> sentBodies = [];
  final List<String> logs = [];
  final Map<String, String> prefs = {};

  Future<HostHttpResponse> _serve(
    String method,
    String url,
    Map<String, String> headers,
    String? body,
  ) async {
    requested.add('$method $url');
    sentHeaders.add(headers);
    sentBodies.add(body);
    final e = routes['$method $url'] ?? _byKey['$method $url'];
    if (e == null) throw StateError('unrecorded request: $method $url');
    return HostHttpResponse(status: e.status, headers: e.headers, body: e.body);
  }

  @override
  Future<HostHttpResponse> httpGet(
    String url, {
    Map<String, String> headers = const {},
  }) => _serve('GET', url, headers, null);

  @override
  Future<HostHttpResponse> httpPost(
    String url, {
    Map<String, String> headers = const {},
    String? body,
  }) => _serve('POST', url, headers, body);

  @override
  List<HtmlMatch> htmlSelect(String html, String css) => selectHtml(html, css);

  @override
  void log(String message) => logs.add(message);

  @override
  Future<String?> prefsGet(String key) async => prefs[key];

  @override
  Future<void> prefsSet(String key, String value) async => prefs[key] = value;
}

/// Index entry for inline test extensions.
MangayomiEntry testEntry({String baseUrl = 'https://site.test'}) =>
    MangayomiEntry.fromJson({
      'id': 42,
      'name': 'Test',
      'lang': 'en',
      'baseUrl': baseUrl,
      'apiUrl': 'https://api.site.test',
      'version': '1.0.0',
      'sourceCodeUrl': 'https://repo.test/test.js',
      'sourceCodeLanguage': 1,
      'itemType': 0,
    });

/// Session running [extension] (converted) on the interpreter engine.
PluginSession sessionFor(
  MangayomiEntry entry,
  String extension,
  PluginHostServices services, {
  JsEngineFactory engine = InterpreterEngine.new,
}) {
  final plugin = MangayomiConverter.convert(entry, extension);
  return PluginSession(
    manifest: plugin.manifest,
    source: plugin.source,
    services: services,
    engineFactory: engine,
  );
}

/// Inline extension whose `getPopular(page)` returns `probe(page)` as the
/// single list item's name (JSON), for exercising shim globals.
String probeExtension(String probeBody) =>
    '''
const mangayomiSources = [];
async function probe(arg) { $probeBody }
class DefaultExtension extends MProvider {
  async getPopular(page) {
    const v = await probe(page);
    return { list: [{ name: JSON.stringify(v), link: "/x" }], hasNextPage: false };
  }
}
''';
