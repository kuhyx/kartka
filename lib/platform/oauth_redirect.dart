/// Completes an OAuth authorization in the system browser (DOCS-contracts §7).
///
/// Android: deep link `kartka://oauth`. Web: the desktop wrapper catches
/// `http://127.0.0.1:8791/oauth` (registered at AniList and MAL, so the port
/// is fixed) and hands the redirect back to the page.
abstract interface class OAuthRedirect {
  /// The redirect URI to register with the provider and send as
  /// `redirect_uri`.
  Uri get redirectUri;

  /// Opens [authorizationUrl] and completes with the full redirect URI the
  /// provider sent back (query and fragment intact; e.g. AniList's implicit
  /// grant puts `access_token` in the fragment). Throws [OAuthCancelled]
  /// on [timeout].
  Future<Uri> authorize(
    Uri authorizationUrl, {
    Duration timeout = const Duration(minutes: 5),
  });
}

/// The user did not finish signing in before the timeout.
class OAuthCancelled implements Exception {
  /// Creates the exception.
  const new();

  @override
  String toString() => 'OAuthCancelled';
}
