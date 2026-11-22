import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:kartka/platform/http_client.dart';
import 'package:kartka/platform/wrapper_protocol.dart';

/// [KartkaHttp] straight to the host (Android).
class DirectKartkaHttp extends KartkaHttp {
  /// Sends through [client].
  new(this.client);

  /// The underlying client.
  final http.Client client;

  @override
  Future<KartkaResponse> send(
    String method,
    Uri url, {
    Map<String, String> headers = const {},
    String? body,
  }) async {
    _check(method, url);
    Future<KartkaResponse> once() {
      final request = http.Request(method, url)
        ..headers.addAll({
          for (final h in headers.entries)
            if (h.key.toLowerCase() != 'user-agent') h.key: h.value,
          // Honest UA, always: hosts like MangaDex reject a spoofed browser.
          'user-agent': kartkaUserAgent,
        });
      if (body != null) request.bodyBytes = utf8.encode(body);
      return _complete(client.send(request), (h) => h);
    }

    try {
      return await once();
    } on http.ClientException catch (e) {
      if (!_readOnly.contains(method) || !_dropped.hasMatch(e.message)) {
        rethrow;
      }
      return await once();
    }
  }

  /// A pooled keep-alive connection the server had already closed: the
  /// request never reached it, so a fresh connection usually succeeds
  /// ("Connection closed before full header was received").
  static final _dropped = RegExp(
    'Connection closed|Connection reset|connection abort',
    caseSensitive: false,
  );

  /// Methods safe to send twice.
  static const _readOnly = {'GET', 'HEAD'};
}

/// [KartkaHttp] through the desktop wrapper's `/proxy` (web build).
///
/// The wrapper sets the User-Agent and adds no `Via`; see
/// [KartkaWrapper.proxyPath] for the wire format.
class ProxyKartkaHttp extends KartkaHttp {
  /// Sends through [client] to the wrapper at [base] (its origin).
  new(this.client, this.base);

  /// The underlying (browser) client.
  final http.Client client;

  /// The wrapper's origin, e.g. `http://127.0.0.1:47391/`.
  final Uri base;

  @override
  Future<KartkaResponse> send(
    String method,
    Uri url, {
    Map<String, String> headers = const {},
    String? body,
  }) async {
    _check(method, url);
    final target = base.replace(
      path: KartkaWrapper.proxyPath,
      queryParameters: {'url': url.toString()},
    );
    final request = http.Request(method, target)
      ..headers.addAll({
        KartkaWrapper.apiHeader: '1',
        for (final h in headers.entries)
          '${KartkaWrapper.requestHeaderPrefix}${h.key.toLowerCase()}': h.value,
      });
    // bodyBytes, not body: setting body would add a text/plain Content-Type
    // the caller did not ask for.
    if (body != null) request.bodyBytes = utf8.encode(body);
    final response = await client.send(request);
    final cause = response.headers[KartkaWrapper.proxyErrorHeader];
    if (response.statusCode == 502 && cause != null) {
      await response.stream.drain<void>();
      throw KartkaNetworkException(cause, url);
    }
    return await _complete(Future.value(response), _unprefix);
  }

  static Map<String, String> _unprefix(Map<String, String> headers) => {
    for (final h in headers.entries)
      if (h.key.startsWith(KartkaWrapper.responseHeaderPrefix))
        h.key.substring(KartkaWrapper.responseHeaderPrefix.length): h.value,
  };
}

void _check(String method, Uri url) {
  checkHttpMethod(method);
  if (url.scheme != 'http' && url.scheme != 'https') {
    throw ArgumentError.value(url, 'url', 'only http(s) is allowed');
  }
}

Future<KartkaResponse> _complete(
  Future<http.StreamedResponse> pending,
  Map<String, String> Function(Map<String, String>) headers,
) async {
  final response = await pending;
  return KartkaResponse(
    statusCode: response.statusCode,
    bodyBytes: await response.stream.toBytes(),
    headers: headers(response.headers),
  );
}
