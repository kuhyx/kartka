/// Strips secrets from text that is about to be shown on screen.
library;

/// An http(s) URL up to its query or fragment, then that query/fragment.
///
/// The tail runs to whitespace, a quote or an angle bracket only: `,` and
/// `)` are legal inside a query, so stopping there could leave a secret
/// half shown. Over-redacting a trailing `)` is the cheaper mistake.
final _urlTail = RegExp(
  r'''(https?://[^\s?#"'<>]*)([?#])[^\s"'<>]*''',
  caseSensitive: false,
);

/// [text] with the query and fragment of every http(s) URL replaced by
/// `?<redacted>` (or `#<redacted>` when there is only a fragment).
///
/// Scheme, host and path stay, so the message still says what failed. A
/// query carries API keys (`?key=`) and Firebase ID tokens (`?auth=`); a
/// fragment carries implicit-grant OAuth tokens (`#access_token=`).
String redactUrlQueries(String text) =>
    text.replaceAllMapped(_urlTail, (m) => '${m[1]}${m[2]}<redacted>');
