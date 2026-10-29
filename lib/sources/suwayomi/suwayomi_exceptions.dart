/// Base class of everything the Suwayomi client throws on purpose.
class SuwayomiException implements Exception {
  /// Creates an exception carrying the server's [message].
  const new(this.message);

  /// Human-readable cause (first GraphQL error line or HTTP status).
  final String message;

  @override
  String toString() => 'SuwayomiException: $message';
}

/// No server URL is configured yet.
class SuwayomiNotConfiguredException extends SuwayomiException {
  /// Creates the exception.
  const new() : super('no server URL configured');
}

/// The server rejected the basic-auth credentials (HTTP 401).
class SuwayomiAuthException extends SuwayomiException {
  /// Creates the exception.
  const new() : super('wrong username or password');
}

/// The server has never seen this manga or chapter and a title search did
/// not find it either, so it has no server-side id to fetch by.
class SuwayomiNotOnServerException extends SuwayomiException {
  /// Creates the exception for [url] of [sourceId]. The message names the
  /// source only: it is logged verbatim (`updates.check`), and diagnostics
  /// carry no URLs.
  new(this.sourceId, this.url) : super('not on the server for $sourceId');

  /// Kartka source id (`suwayomi:<id>`).
  final String sourceId;

  /// The manga or chapter URL that could not be resolved.
  final String url;
}
