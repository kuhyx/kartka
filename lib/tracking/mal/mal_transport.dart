/// Plain HTTP shapes the MyAnimeList client speaks.
///
/// The client depends on a [MalSend] function rather than on `KartkaHttp`
/// directly; `mal_feature.dart` adapts `KartkaHttp` to it, so the
/// protocol code stays testable with recorded fixtures.
library;

/// HTTP methods MAL needs.
enum MalMethod {
  /// GET.
  get,

  /// POST.
  post,

  /// PATCH.
  patch,
}

/// One outgoing request.
class MalRequest {
  /// Creates a request.
  const new(this.method, this.url, {this.headers = const {}, this.body});

  /// HTTP method.
  final MalMethod method;

  /// Absolute URL.
  final Uri url;

  /// Request headers.
  final Map<String, String> headers;

  /// Request body, already encoded.
  final String? body;
}

/// One response.
class MalResponse {
  /// Creates a response.
  const new(this.statusCode, this.body);

  /// HTTP status code.
  final int statusCode;

  /// Body decoded as UTF-8.
  final String body;

  /// Whether [statusCode] is 2xx.
  bool get ok => statusCode >= 200 && statusCode < 300;
}

/// Sends one request.
typedef MalSend = Future<MalResponse> Function(MalRequest request);

/// Content type of every MAL write (token endpoint and list updates).
const malFormContentType = 'application/x-www-form-urlencoded';

/// Encodes [fields] as an `application/x-www-form-urlencoded` body.
String malForm(Map<String, String> fields) =>
    Uri(queryParameters: fields).query;

/// A MAL request failed.
class MalException implements Exception {
  /// Creates an exception with an optional HTTP [statusCode].
  const new(this.message, {this.statusCode});

  /// What went wrong.
  final String message;

  /// HTTP status, when the failure came from a response.
  final int? statusCode;

  /// Name shown in [toString].
  String get kind => 'MalException';

  @override
  String toString() =>
      statusCode == null ? '$kind: $message' : '$kind($statusCode): $message';
}

/// Not logged in, or MAL refused the credentials.
class MalAuthException extends MalException {
  /// Creates an auth failure.
  const new(super.message, {super.statusCode});

  @override
  String get kind => 'MalAuthException';
}
