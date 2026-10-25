import 'dart:convert';

import 'package:kartka/platform/http_client.dart';
import 'package:kartka/platform/key_value_store.dart';

/// Hosts kuhy finished "Open in WebView" on (docs/DOCS-contracts-webview.md
/// §5). Only these get WebView cookies; a subdomain counts as its host.
class WebViewHosts {
  /// Persists in [kv] under [key].
  new(this.kv);

  /// Kv key: a JSON list of lower-case host names.
  static const key = 'webview.hosts';

  /// Backing store (device-local, never synced).
  final KeyValueStore kv;

  Set<String>? _hosts;

  Future<Set<String>> _load() async {
    if (_hosts case final hosts?) return hosts;
    Object? raw;
    try {
      raw = jsonDecode(await kv.get(key) ?? '[]');
    } on FormatException {
      raw = null;
    }
    return _hosts = {
      if (raw is List)
        for (final h in raw)
          if (h is String) h,
    };
  }

  /// Adds [url]'s host.
  Future<void> add(Uri url) async {
    final hosts = await _load();
    if (hosts.add(url.host.toLowerCase())) {
      await kv.set(key, jsonEncode(hosts.toList()));
    }
  }

  /// Whether [url]'s host, or a parent domain of it, was added.
  Future<bool> covers(Uri url) async {
    final host = url.host.toLowerCase();
    return (await _load()).any((h) => host == h || host.endsWith('.$h'));
  }
}

/// Adds the WebView's cookies to requests for [WebViewHosts] (Android).
///
/// [cookieFor] returns the `Cookie` header the WebView would send to a URL
/// (`CookieManager.getCookie`), so the WebView applies domain, path and
/// secure matching itself. A caller-supplied cookie is kept in front.
class CookieKartkaHttp extends KartkaHttp {
  /// Wraps [inner].
  new(this.inner, this.hosts, {required this.cookieFor});

  /// The real client.
  final KartkaHttp inner;

  /// Where cookies apply.
  final WebViewHosts hosts;

  /// The WebView cookie header for a URL ('' or null when none).
  final Future<String?> Function(Uri url) cookieFor;

  @override
  Future<KartkaResponse> send(
    String method,
    Uri url, {
    Map<String, String> headers = const {},
    String? body,
  }) async {
    var out = headers;
    if (await hosts.covers(url)) {
      final jar = await cookieFor(url) ?? '';
      if (jar.isNotEmpty) {
        final name = headers.keys.firstWhere(
          (k) => k.toLowerCase() == 'cookie',
          orElse: () => 'Cookie',
        );
        final mine = headers[name];
        out = {...headers, name: mine == null ? jar : '$mine; $jar'};
      }
    }
    return await inner.send(method, url, headers: out, body: body);
  }
}
