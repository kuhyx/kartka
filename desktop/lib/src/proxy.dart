import 'dart:async';
import 'dart:io';

import 'package:kartka_desktop/src/protocol.dart';

/// Upstream request headers the proxy forwards (after the
/// [requestHeaderPrefix] is stripped). Any other `x-` API header is also
/// forwarded, except the forwarding/identity ones in [_neverForward].
const forwardedRequestHeaders = {
  'accept',
  'accept-language',
  'authorization',
  'cache-control',
  'content-type',
  'cookie',
  'if-modified-since',
  'if-none-match',
  'origin',
  'range',
  'referer',
};

/// Never sent upstream, whatever the page asks: the proxy must look like a
/// direct client (no Via / forwarding chain) with the honest Kartka UA.
const _neverForward = {
  'user-agent',
  'via',
  'forwarded',
  'x-forwarded-for',
  'x-forwarded-host',
  'x-forwarded-proto',
  'x-real-ip',
};

/// Upstream response headers not relayed (hop-by-hop, or describing a body
/// encoding HttpClient has already undone).
const _hopByHop = {
  'connection',
  'content-encoding',
  'content-length',
  'keep-alive',
  'transfer-encoding',
};

/// `<METHOD> /proxy?url=<absolute http(s) URL>`: forwards the method, body
/// and allowed headers; relays status, body and headers (prefixed).
class ProxyRoute {
  /// Forwards through [client].
  new(this.client) {
    client
      ..userAgent = null
      ..connectionTimeout = const Duration(seconds: 20);
  }

  /// Upstream client (follows redirects for GET/HEAD).
  final HttpClient client;

  /// Releases the client.
  void close() => client.close(force: true);

  /// Whether [name] (lower-case, prefix stripped) may go upstream.
  static bool forwards(String name) =>
      !_neverForward.contains(name) &&
      (forwardedRequestHeaders.contains(name) || name.startsWith('x-'));

  /// Proxies [request].
  Future<void> handle(HttpRequest request) async {
    final response = request.response;
    if (!proxyMethods.contains(request.method)) {
      response.statusCode = HttpStatus.methodNotAllowed;
      return;
    }
    final target = Uri.tryParse(request.uri.queryParameters['url'] ?? '');
    if (target == null ||
        (target.scheme != 'http' && target.scheme != 'https') ||
        target.host.isEmpty ||
        _isSelf(target, request.connectionInfo!.localPort)) {
      await request.drain<void>();
      response.statusCode = HttpStatus.badRequest;
      return;
    }
    final body = await request.fold<List<int>>([], (a, b) => a..addAll(b));
    final HttpClientResponse upstream;
    try {
      final out = await client.openUrl(request.method, target);
      request.headers.forEach((name, values) {
        if (!name.startsWith(requestHeaderPrefix)) return;
        final real = name.substring(requestHeaderPrefix.length);
        if (forwards(real)) out.headers.set(real, values.join(', '));
      });
      out.headers.set('user-agent', kartkaUserAgent);
      if (body.isNotEmpty) {
        out
          ..contentLength = body.length
          ..add(body);
      }
      upstream = await out.close().timeout(const Duration(seconds: 60));
    } on Object catch (e) {
      response
        ..statusCode = HttpStatus.badGateway
        ..headers.set(proxyErrorHeader, e.runtimeType.toString());
      return;
    }
    response.statusCode = upstream.statusCode;
    upstream.headers.forEach((name, values) {
      if (_hopByHop.contains(name)) return;
      response.headers.set('$responseHeaderPrefix$name', values.join(', '));
      if (name == 'content-type') response.headers.set(name, values.first);
    });
    await response.addStream(upstream);
  }

  static bool _isSelf(Uri target, int ownPort) =>
      target.port == ownPort &&
      (target.host == '127.0.0.1' || target.host == 'localhost');
}
