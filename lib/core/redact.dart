/// Strips secrets from text that is about to be shown on screen or logged.
library;

/// An http(s) URL up to its query or fragment, then that query/fragment.
///
/// The tail runs to whitespace, a quote or an angle bracket only: `,` and
/// `)` are legal inside a query, so stopping there could leave a secret
/// half shown. Over-redacting a trailing `)` is the cheaper mistake.
///
/// A tail that is already `<redacted>` is left alone, so redacting twice
/// (an entry read back and re-serialised) changes nothing.
final _urlTail = RegExp(
  r'''(https?://[^\s?#"'<>]*)([?#])(?!<redacted>)[^\s"'<>]*''',
  caseSensitive: false,
);

/// The userinfo of an http(s) URL: everything before an `@` that is still
/// inside the authority (no `/`, `?` or `#` yet), so `/p/@me` is a path.
final _userInfo = RegExp(
  r'''(https?://)[^\s/?#"'<>@]*@''',
  caseSensitive: false,
);

/// [text] with the query and fragment of every http(s) URL replaced by
/// `?<redacted>` (or `#<redacted>` when there is only a fragment), and its
/// userinfo (`user:pass@`) by `<redacted>@`.
///
/// Scheme, host and path stay, so the message still says what failed. A
/// query carries API keys (`?key=`) and Firebase ID tokens (`?auth=`); a
/// fragment carries implicit-grant OAuth tokens (`#access_token=`); userinfo
/// carries basic-auth credentials. The query pass runs first: its URL match
/// stops at `<`, so a `<redacted>@` inserted earlier would shield the query.
String redactUrlQueries(String text) => text
    .replaceAllMapped(_urlTail, (m) => '${m[1]}${m[2]}<redacted>')
    .replaceAllMapped(_userInfo, (m) => '${m[1]}<redacted>@');
