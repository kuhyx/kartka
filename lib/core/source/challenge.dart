/// Browser challenges and the "Open in WebView" target
/// (docs/DOCS-contracts-webview.md §2, §7).
library;

/// A site answered with a Cloudflare / captcha / DDoS-Guard interstitial.
///
/// Kartka never solves one (DOCS-spec "Never"): the UI offers "Open in
/// WebView" so kuhy can, and kartka retries afterwards. Other errors (for
/// example `PluginChallengeException`) implement this interface so UI
/// code only ever checks `error is ChallengeRequired`.
class ChallengeRequired implements Exception {
  /// A challenge of [kind] (`cloudflare`, `captcha`, `ddos-guard`) at [url].
  const new(this.url, this.kind);

  /// The page that showed the challenge; open this one in the WebView.
  final Uri url;

  /// What kind of interstitial it was.
  final String kind;

  @override
  String toString() => 'ChallengeRequired($kind, $url)';
}

/// A source with a site kuhy can open in the WebView (to log in or pass a
/// challenge). Optional: `MangaSource` (contracts §2) has no base URL.
abstract interface class WebViewTarget {
  /// The site's home page.
  Uri get webViewUrl;
}
