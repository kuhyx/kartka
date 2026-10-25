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
  /// Forwards through [client]; `_log` gets failures (never a target URL,
  /// whose query can hold a credential such as RTDB's `?auth=`).
  new(this.client, this._log, {this.cookieFor}) {
    client
      ..userAgent = null
      ..connectionTimeout = const Duration(seconds: 20);
  }

  /// Upstream client (follows redirects for GET/HEAD).
  final HttpClient client;

  /// Cookies of the engine profile for a target ("Open in WebView" hosts,
  /// docs/DOCS-contracts-webview.md §6); null when none apply.
  final Future<String?> Function(Uri target)? cookieFor;

  final void Function(String line) _log;

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
      final jar = await _jar(target);
      if (jar != null) {
        final mine = out.headers.value('cookie');
        out.headers.set('cookie', mine == null ? jar : '$mine; $jar');
      }
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
    try {
      await response.addStream(upstream);
    } on Object catch (e) {
      // The headers are out, so the status cannot change any more: the
      // truncated body is the error. Escaping would kill the wrapper.
      _log('kartka-desktop: /proxy: upstream cut mid-body (${e.runtimeType})');
    }
  }

  /// Never fails the request: no engine simply means no extra cookies.
  Future<String?> _jar(Uri target) async {
    try {
      return await cookieFor?.call(target);
    } on Object catch (e) {
      _log(
        'kartka-desktop: /proxy: engine cookies unavailable (${e.runtimeType})',
      );
      return null;
    }
  }

  static bool _isSelf(Uri target, int ownPort) =>
      target.port == ownPort &&
      (target.host == '127.0.0.1' || target.host == 'localhost');
}
