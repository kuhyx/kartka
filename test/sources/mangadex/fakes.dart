import 'package:kartka/platform/memory/memory_fakes.dart';

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

/// A FakeKartkaHttp serving [routes] by `path` or `path?offset=N`.
///
/// A route may hold several responses; they are served in order and the
/// last one repeats. An unknown route throws, so no request goes unnoticed.
FakeKartkaHttp fixtureHttp(Map<String, List<Canned>> routes) =>
    FakeKartkaHttp((req) {
      final url = req.url;
      final offset = url.queryParameters['offset'];
      final key = offset == null ? url.path : '${url.path}?offset=$offset';
      final list = routes[key] ?? routes[url.path];
      if (list == null) throw StateError('no fixture for $url');
      final c = list.length > 1 ? list.removeAt(0) : list.single;
      return FakeKartkaHttp.text(c.body, status: c.status, headers: c.headers);
    });
