import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:kartka/platform/oauth_redirect.dart';
import 'package:kartka/platform/wrapper_protocol.dart';

/// [OAuthRedirect] via the `kartka://oauth` deep link (Android).
class DeepLinkOAuthRedirect implements OAuthRedirect {
  /// Opens URLs with [launch] and listens for app links on [links].
  new({required this.launch, required this.links});

  /// Opens a URL in the system browser; `false` when it could not.
  final Future<bool> Function(Uri url) launch;

  /// Every deep link the app receives.
  final Stream<Uri> links;

  @override
  Uri get redirectUri => Uri.parse('kartka://oauth');

  @override
  Future<Uri> authorize(
    Uri authorizationUrl, {
    Duration timeout = const Duration(minutes: 5),
  }) async {
    // Listen before launching: the browser can bounce back immediately.
    final back = links
        .firstWhere((u) => u.scheme == 'kartka' && u.host == 'oauth')
        .timeout(timeout);
    if (!await launch(authorizationUrl)) {
      unawaited(back.then((_) {}, onError: (_) {}));
      throw const OAuthCancelled();
    }
    try {
      return await back;
    } on TimeoutException {
      throw const OAuthCancelled();
    }
  }
}

/// [OAuthRedirect] via the desktop wrapper's `/oauth` page (web build).
///
/// The provider redirects the tab to `http://127.0.0.1:8791/oauth`; that
/// page posts its full URL (fragment included: AniList's implicit grant
/// puts the token there, and fragments never reach a server) to
/// `/oauth/result`, which this polls.
class WrapperOAuthRedirect implements OAuthRedirect {
  /// Polls the wrapper at [base] through [client]; [open] opens a tab.
  new({
    required this.client,
    required this.base,
    required this.open,
    this.pollInterval = const Duration(seconds: 1),
  });

  /// Browser HTTP client.
  final http.Client client;

  /// The wrapper's origin.
  final Uri base;

  /// Opens a URL in a new browser tab.
  final void Function(Uri url) open;

  /// Delay between polls.
  final Duration pollInterval;

  @override
  Uri get redirectUri => base.replace(path: KartkaWrapper.oauthPath);

  Uri get _result => base.replace(path: KartkaWrapper.oauthResultPath);

  Future<http.Response> _call(String method) async =>
      await http.Response.fromStream(
        await client.send(
          http.Request(method, _result)..headers[KartkaWrapper.apiHeader] = '1',
        ),
      );

  @override
  Future<Uri> authorize(
    Uri authorizationUrl, {
    Duration timeout = const Duration(minutes: 5),
  }) async {
    await _call('DELETE');
    open(authorizationUrl);
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final r = await _call('GET');
      if (r.statusCode == 200) return Uri.parse(r.body);
      await Future<void>.delayed(pollInterval);
    }
    throw const OAuthCancelled();
  }
}
