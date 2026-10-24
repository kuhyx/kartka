import 'dart:convert';
import 'dart:typed_data';

import 'package:kartka/platform/http_client.dart';
import 'package:kartka/platform/key_value_store.dart';

import 'fixtures.dart';

/// A canned response: a fixture file or literal body, plus status/headers.
class Canned {
  /// Serves fixture [file].
  new file(String file, {this.status = 200, this.headers = const {}})
    : body = fixture(file);

  /// Serves [body] as is.
  const new body(this.body, {this.status = 200, this.headers = const {}});

  /// Response body.
  final String body;

  /// Status code.
  final int status;

  /// Lower-cased response headers.
  final Map<String, String> headers;
}

/// KartkaHttp that serves fixtures by `path` or `path?offset=N`.
///
/// A route may hold several responses; they are served in order and the
/// last one repeats.
class FakeHttp extends KartkaHttp {
  /// Creates the fake over [routes].
  new(this.routes);

  /// Route key -> responses.
  final Map<String, List<Canned>> routes;

  /// Every request made, in order.
  final List<Uri> requests = [];

  /// Headers of every request, in order.
  final List<Map<String, String>> sentHeaders = [];

  @override
  Future<KartkaResponse> send(
    String method,
    Uri url, {
    Map<String, String> headers = const {},
    String? body,
  }) async {
    if (method != 'GET') throw UnimplementedError('MangaDex never ${method}s');
    requests.add(url);
    sentHeaders.add(headers);
    final offset = url.queryParameters['offset'];
    final key = offset == null ? url.path : '${url.path}?offset=$offset';
    final list = routes[key] ?? routes[url.path];
    if (list == null) throw StateError('no fixture for $url');
    final c = list.length > 1 ? list.removeAt(0) : list.single;
    return KartkaResponse(
      statusCode: c.status,
      bodyBytes: Uint8List.fromList(utf8.encode(c.body)),
      headers: c.headers,
    );
  }
}

/// In-memory KeyValueStore.
class FakeKv implements KeyValueStore {
  /// Stored entries.
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
