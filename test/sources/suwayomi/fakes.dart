import 'dart:convert';
import 'dart:io';

import 'package:kartka/platform/memory/memory_platform.dart';
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
/// answers 599, so unexpected requests are loud.
FakeKartkaHttp fixtureHttp(Iterable<String> names) {
  final byKey = {
    for (final name in names)
      _key(fixture(name)['request']! as Map<String, Object?>): fixture(name),
  };
  return FakeKartkaHttp((request) {
    final key = _key(jsonDecode(request.body!) as Map<String, Object?>);
    final f = byKey[key];
    if (request.method != 'POST' || f == null) {
      return FakeKartkaHttp.text('no fixture for $key', status: 599);
    }
    final response = f['response'];
    return FakeKartkaHttp.text(
      response is String ? response : jsonEncode(response),
      status: f['status']! as int,
    );
  });
}

String _key(Map<String, Object?> req) =>
    '${req['operationName']} ${canonical(req['variables'])}';

/// Answers every request with [status] and [body].
FakeKartkaHttp cannedHttp(int status, String body) =>
    FakeKartkaHttp((_) => FakeKartkaHttp.text(body, status: status));

/// Decoded GraphQL bodies of every request [http] received.
List<Map<String, Object?>> bodies(FakeKartkaHttp http) => [
  for (final r in http.requests) jsonDecode(r.body!) as Map<String, Object?>,
];
