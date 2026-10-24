import 'dart:typed_data';

import 'package:kartka/core/models/models.dart';
import 'package:kartka/platform/blob_store.dart';
import 'package:kartka/platform/http_client.dart';
import 'package:kartka/platform/image_headers.dart';

/// URL scheme of a page stored in [BlobStore] (DOCS-contracts §11).
///
/// Not `blob:`, which is the browser's object-URL scheme on web.
const kartkaBlobScheme = 'kartka-blob';

/// The [PageRef.imageUrl] for a page stored under [blobKey].
String blobPageUrl(String blobKey) {
  checkBlobKey(blobKey);
  return '$kartkaBlobScheme://$blobKey';
}

/// Loads page images from either an offline blob or the network.
///
/// The one resolver the reader, downloads and local sources share, so an
/// offline page and an online one are indistinguishable to the UI.
class PageImageLoader {
  /// Creates a loader over [http] and [blobs]; [imageHeaders] is normally
  /// `registry.all<ImageHeaders>()`.
  const new({
    required this.http,
    required this.blobs,
    this.imageHeaders = const [],
  });

  /// Network client for `http(s)` pages.
  final KartkaHttp http;

  /// Offline store for `kartka-blob` pages.
  final BlobStore blobs;

  /// Header providers merged in order before the page's own headers.
  final List<ImageHeaders> imageHeaders;

  /// Request headers for [url]: every provider in order, then [own] wins.
  Map<String, String> headersFor(String url, Map<String, String> own) => {
    for (final provider in imageHeaders) ...provider.forUrl(url),
    ...own,
  };

  /// The image bytes of [page].
  ///
  /// Throws [ArgumentError] for an unknown scheme, [StateError] for a
  /// missing blob and [KartkaHttpException] for a non-2xx response.
  Future<Uint8List> load(PageRef page) async {
    const prefix = '$kartkaBlobScheme://';
    if (page.imageUrl.startsWith(prefix)) {
      final key = page.imageUrl.substring(prefix.length);
      checkBlobKey(key);
      final bytes = await blobs.get(key);
      if (bytes == null) throw StateError('missing blob $key');
      return bytes;
    }
    final url = Uri.parse(page.imageUrl);
    if (url.scheme != 'http' && url.scheme != 'https') {
      throw ArgumentError.value(page.imageUrl, 'imageUrl', 'unknown scheme');
    }
    final response = await http.get(
      url,
      headers: headersFor(page.imageUrl, page.headers),
    );
    if (!response.ok) throw KartkaHttpException(url, response.statusCode);
    return response.bodyBytes;
  }
}
