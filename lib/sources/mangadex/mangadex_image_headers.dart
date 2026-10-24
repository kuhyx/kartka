import 'package:kartka/platform/http_client.dart';
import 'package:kartka/platform/image_headers.dart';

/// Sends the honest User-Agent to MangaDex image hosts: covers on
/// `uploads.mangadex.org` and pages on MangaDex@Home `*.mangadex.network`.
class MangadexImageHeaders implements ImageHeaders {
  /// Creates the provider.
  const new();

  static bool _ours(String host) =>
      host == 'mangadex.org' ||
      host.endsWith('.mangadex.org') ||
      host.endsWith('.mangadex.network');

  @override
  Map<String, String> forUrl(String url) {
    final host = Uri.tryParse(url)?.host ?? '';
    return _ours(host) ? const {'User-Agent': kartkaUserAgent} : const {};
  }
}
