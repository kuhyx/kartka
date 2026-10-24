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
///
/// Implementations extend this class and override [send] only; [get] and
/// [post] are thin wrappers over it.
abstract class KartkaHttp {
  /// Methods [send] accepts (the desktop proxy allows exactly these).
  static const methods = {'GET', 'HEAD', 'POST', 'PUT', 'PATCH', 'DELETE'};

  /// Sends [method] (one of [methods]) to [url] with extra request
  /// [headers] and an optional UTF-8 [body]. `Content-Type` is the caller's
  /// to set (e.g. `application/x-www-form-urlencoded` for MAL).
  Future<KartkaResponse> send(
    String method,
    Uri url, {
    Map<String, String> headers = const {},
    String? body,
  });

  /// GETs [url] with extra request [headers].
  Future<KartkaResponse> get(
    Uri url, {
    Map<String, String> headers = const {},
  }) => send('GET', url, headers: headers);

  /// POSTs [body] (UTF-8) to [url] with extra request [headers].
  Future<KartkaResponse> post(
    Uri url, {
    Map<String, String> headers = const {},
    String? body,
  }) => send('POST', url, headers: headers, body: body);
}

/// Throws [ArgumentError] unless [method] is one of [KartkaHttp.methods].
void checkHttpMethod(String method) {
  if (!KartkaHttp.methods.contains(method)) {
    throw ArgumentError.value(method, 'method', 'not allowed');
  }
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
