import 'dart:convert';
import 'dart:typed_data';

/// User-Agent every request carries, direct or through the desktop proxy.
///
/// Honest on purpose: MangaDex (and others) reject a spoofed browser UA.
const kartkaUserAgent = 'Kartka/0.1 (+https://github.com/kuhyx/kartka)';

/// The only HTTP client sources, plugins and trackers use (DOCS-contracts §2).
///
/// Android talks to hosts directly; the web build routes every request
/// through the desktop wrapper's `/proxy` (CORS, and headers like `Referer`
/// that a browser page may not set). Callers cannot tell which.
abstract interface class KartkaHttp {
  /// GETs [url] with extra request [headers].
  Future<KartkaResponse> get(Uri url, {Map<String, String> headers});

  /// POSTs [body] (UTF-8) to [url] with extra request [headers].
  Future<KartkaResponse> post(
    Uri url, {
    Map<String, String> headers,
    String? body,
  });
}

/// A complete HTTP response.
class KartkaResponse {
  /// Creates a response.
  new({
    required this.statusCode,
    required this.bodyBytes,
    this.headers = const {},
  });

  /// Upstream status code.
  final int statusCode;

  /// Response headers, lower-cased names.
  final Map<String, String> headers;

  /// Raw body (images, archives).
  final Uint8List bodyBytes;

  /// Body decoded as UTF-8; malformed bytes become U+FFFD.
  String get body => utf8.decode(bodyBytes, allowMalformed: true);

  /// Whether [statusCode] is 2xx.
  bool get ok => statusCode >= 200 && statusCode < 300;
}

/// Thrown by callers that need a 2xx and did not get one.
class KartkaHttpException implements Exception {
  /// Creates the exception for [url] answering [statusCode].
  const new(this.url, this.statusCode);

  /// The requested URL.
  final Uri url;

  /// The status that was not 2xx.
  final int statusCode;

  @override
  String toString() => 'KartkaHttpException($statusCode, $url)';
}
