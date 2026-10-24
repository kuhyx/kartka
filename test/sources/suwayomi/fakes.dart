import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:kartka/platform/http_client.dart';
import 'package:kartka/platform/key_value_store.dart';
import 'package:kartka/sources/suwayomi/suwayomi_settings.dart';

/// Settings matching the server the fixtures were recorded from.
const fixtureSettings = SuwayomiSettings(
  serverUrl: 'http://127.0.0.1:4599/',
  username: 'kartka',
  password: 'fixture',
);

/// MangaDex (EN) on the fixture server.
const mangadexEn = '2499283573021220255';

/// Reads `test/fixtures/suwayomi/<name>.json`.
Map<String, Object?> fixture(String name) =>
    jsonDecode(File('test/fixtures/suwayomi/$name.json').readAsStringSync())
        as Map<String, Object?>;

/// Every fixture name in the directory.
List<String> fixtureNames() => [
  for (final f in Directory('test/fixtures/suwayomi').listSync())
    if (f.path.endsWith('.json'))
      f.uri.pathSegments.last.replaceFirst('.json', ''),
];

/// JSON with map keys sorted, so equal values compare equal as strings.
String canonical(Object? value) => jsonEncode(_sorted(value));

Object? _sorted(Object? v) => switch (v) {
  final Map<String, Object?> m => {
    for (final k in m.keys.toList()..sort()) k: _sorted(m[k]),
  },
  final List<Object?> l => [for (final e in l) _sorted(e)],
  _ => v,
};

/// Serves recorded fixtures by (operationName, variables); anything else
/// fails the test with a 599, so unexpected requests are loud.
class FixtureHttp extends KartkaHttp {
  /// Serves the named fixtures.
  new(Iterable<String> names) {
    for (final name in names) add(name);
  }

  final _byRequest = <String, Map<String, Object?>>{};

  /// Bodies of every POST, decoded.
  final requests = <Map<String, Object?>>[];

  /// Headers of every POST.
  final headers = <Map<String, String>>[];

  /// Adds (or replaces) the fixture [name].
  void add(String name) {
    final f = fixture(name);
    final req = f['request']! as Map<String, Object?>;
    _byRequest[_key(req)] = f;
  }

  static String _key(Map<String, Object?> req) =>
      '${req['operationName']} ${canonical(req['variables'])}';

  @override
  Future<KartkaResponse> send(
    String method,
    Uri url, {
    Map<String, String> headers = const {},
    String? body,
  }) async {
    if (method != 'POST') throw UnsupportedError('$method $url');
    final req = jsonDecode(body!) as Map<String, Object?>;
    requests.add(req);
    this.headers.add(headers);
    final f = _byRequest[_key(req)];
    if (f == null) return _response(599, 'no fixture for ${_key(req)}');
    final response = f['response'];
    return _response(
      f['status']! as int,
      response is String ? response : jsonEncode(response),
    );
  }
}

KartkaResponse _response(int status, String body) => KartkaResponse(
  statusCode: status,
  bodyBytes: Uint8List.fromList(utf8.encode(body)),
);

/// Answers every request with [status] and [body].
class CannedHttp extends KartkaHttp {
  /// Creates the fake.
  new(this.status, this.body);

  /// Status to answer with.
  final int status;

  /// Body to answer with.
  final String body;

  @override
  Future<KartkaResponse> send(
    String method,
    Uri url, {
    Map<String, String> headers = const {},
    String? body,
  }) async => _response(status, this.body);
}

/// In-memory [KeyValueStore].
class MemoryKv implements KeyValueStore {
  /// Stored values.
  final values = <String, String>{};

  @override
  Future<String?> get(String key) async => values[key];

  @override
  Future<void> set(String key, String value) async => values[key] = value;

  @override
  Future<void> remove(String key) async => values.remove(key);

  @override
  Future<Map<String, String>> entries({String prefix = ''}) async => {
    for (final e in values.entries)
      if (e.key.startsWith(prefix)) e.key: e.value,
  };
}
