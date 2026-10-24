import 'dart:convert';
import 'dart:io';

import 'package:kartka_desktop/src/protocol.dart';

/// The page the provider redirects to. Fragments never reach a server
/// (AniList's implicit grant puts the token there), so the page posts its
/// own full URL back to the result slot.
const oauthPage =
    '''
<!doctype html>
<meta charset="utf-8">
<title>Kartka sign-in</title>
<p id="s">Finishing sign-in...</p>
<script>
fetch("$oauthResultPath", {
  method: "POST",
  headers: {"$apiHeader": "1", "content-type": "text/plain"},
  body: location.href,
}).then(function (r) {
  document.getElementById("s").textContent = r.ok
    ? "Signed in. You can close this tab."
    : "Sign-in failed (" + r.status + ").";
  if (r.ok) setTimeout(function () { window.close(); }, 800);
});
</script>
''';

/// `/oauth` (the page) and `/oauth/result` (a one-entry slot).
class OAuthRoutes {
  /// Accepts redirects to this server on [port].
  new(this.port);

  /// The bound port; only `http://127.0.0.1:<port>/oauth...` URLs are kept.
  final int port;

  String? _result;

  /// Handles both paths.
  Future<void> handle(HttpRequest request) async {
    final response = request.response;
    if (request.uri.path == oauthPath) {
      if (request.method != 'GET') {
        response.statusCode = HttpStatus.methodNotAllowed;
        return;
      }
      response
        ..headers.contentType = ContentType.html
        ..write(oauthPage);
      return;
    }
    switch (request.method) {
      case 'POST':
        final body = await utf8.decodeStream(request);
        final ok =
            body.length <= 8192 &&
            (body.startsWith('http://127.0.0.1:$port$oauthPath') ||
                body.startsWith('http://localhost:$port$oauthPath'));
        if (ok) _result = body;
        response.statusCode = ok ? HttpStatus.noContent : HttpStatus.badRequest;
      case 'GET':
        final result = _result;
        _result = null;
        if (result == null) {
          response.statusCode = HttpStatus.noContent;
        } else {
          response
            ..headers.contentType = ContentType.text
            ..write(result);
        }
      case 'DELETE':
        _result = null;
        response.statusCode = HttpStatus.noContent;
      default:
        response.statusCode = HttpStatus.methodNotAllowed;
    }
  }
}
