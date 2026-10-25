import 'dart:convert';
import 'dart:io';

import 'package:kartka_desktop/src/cdp.dart';
import 'package:kartka_desktop/src/engine.dart';

/// Largest JSON body accepted (expressions are small).
const int _maxBody = 1 << 20;

/// Whether the engine may open [url]: `data:`, or http(s) to a non-loopback
/// host. [allowLoopback] (tests only) admits loopback, but never this
/// wrapper's own [ownPort]: a page there could call its API.
bool engineUrlAllowed(Uri url, int ownPort, {bool allowLoopback = false}) {
  if (url.scheme == 'data') return true;
  if (url.scheme != 'http' && url.scheme != 'https') return false;
  final host = url.host.toLowerCase();
  final loopback =
      host == 'localhost' ||
      host.endsWith('.localhost') ||
      host.startsWith('127.') ||
      host == '::1' ||
      host == '0.0.0.0';
  if (host.isEmpty) return false;
  if (!loopback) return true;
  return allowLoopback && url.port != ownPort;
}

/// `/engine/*` (docs/DOCS-contracts-webview.md §6). The server has already
/// applied the Host / Origin / `x-kartka` checks.
class EngineRoutes {
  /// Drives [engine]; [allowLoopback] is for tests.
  new(this.engine, {this.allowLoopback = false});

  /// The engine behind the routes.
  final EngineHost engine;

  /// See [engineUrlAllowed].
  final bool allowLoopback;

  /// Handles [request] (path under `/engine`).
  Future<void> handle(HttpRequest request) async {
    final res = request.response;
    try {
      await _route(request, request.uri.pathSegments.skip(1).toList());
    } on EngineError catch (e) {
      _json(res, e.status, {'error': e.code});
    } on CdpException catch (e) {
      _json(res, HttpStatus.badGateway, {'error': e.message});
    } on FormatException {
      _json(res, HttpStatus.badRequest, {'error': 'bad-request'});
    }
  }

  Future<void> _route(HttpRequest request, List<String> s) async {
    final res = request.response;
    final method = request.method;
    if (s.length == 1 && s[0] == 'page' && method == 'POST') {
      await request.drain<void>();
      return _json(res, 200, {'id': await engine.createPage()});
    }
    if (s.length == 2 && s[0] == 'page' && method == 'DELETE') {
      await request.drain<void>();
      await engine.closePage(s[1]);
      res.statusCode = HttpStatus.noContent;
      return;
    }
    if (method != 'POST') {
      await request.drain<void>();
      res.statusCode = HttpStatus.notFound;
      return;
    }
    final body = await _body(request);
    if (s.length == 3 && s[0] == 'page' && s[2] == 'navigate') {
      await engine.navigate(s[1], _url(request, body), _headers(body));
      res.statusCode = HttpStatus.noContent;
    } else if (s.length == 3 && s[0] == 'page' && s[2] == 'evaluate') {
      final expression = body['expression'];
      if (expression is! String) throw const FormatException('expression');
      _json(res, 200, {'value': await engine.evaluate(s[1], expression)});
    } else if (s.length == 1 && s[0] == 'open') {
      await engine.open(_url(request, body));
      res.statusCode = HttpStatus.accepted;
    } else if (s.length == 1 && s[0] == 'finish') {
      await engine.finish(_url(request, body));
      res.statusCode = HttpStatus.noContent;
    } else {
      res.statusCode = HttpStatus.notFound;
    }
  }

  Uri _url(HttpRequest request, Map<String, Object?> body) {
    final url = Uri.tryParse('${body['url']}');
    final own = request.connectionInfo!.localPort;
    if (url == null ||
        !engineUrlAllowed(url, own, allowLoopback: allowLoopback)) {
      throw const EngineError(HttpStatus.badRequest, 'url-not-allowed');
    }
    return url;
  }

  static Map<String, String> _headers(Map<String, Object?> body) {
    final h = body['headers'];
    return h is Map
        ? {for (final e in h.entries) '${e.key}': '${e.value}'}
        : const {};
  }

  static Future<Map<String, Object?>> _body(HttpRequest request) async {
    final bytes = <int>[];
    await for (final chunk in request) {
      bytes.addAll(chunk);
      if (bytes.length > _maxBody) throw const FormatException('too large');
    }
    final json = jsonDecode(utf8.decode(bytes));
    if (json is! Map) throw const FormatException('not an object');
    return json.cast<String, Object?>();
  }

  static void _json(HttpResponse res, int status, Object? value) {
    res
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(value));
  }
}
