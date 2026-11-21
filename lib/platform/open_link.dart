import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a URL; `false` when nothing could open it.
typedef UrlLaunch = Future<bool> Function(Uri url);

Future<bool> _browser(Uri url) => launchUrl(
  url,
  mode: LaunchMode.externalApplication,
  webOnlyWindowName: '_blank',
);

/// Opens [url] in the system browser, best effort: a phone with no browser
/// (kuhy's has none) makes url_launcher throw ACTIVITY_NOT_FOUND, which must
/// not escape as an uncaught error. Nothing opens then, by design: an in-app
/// WebView fallback would hand back the browser the phone deliberately lacks.
Future<void> openLinkQuietly(Uri url, {UrlLaunch launch = _browser}) async {
  try {
    await launch(url);
  } on PlatformException {
    // No app handles the URL.
  }
}
