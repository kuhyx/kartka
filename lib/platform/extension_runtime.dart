import 'dart:typed_data';

/// The in-app runtime for Tachiyomi/Keiyoushi extension APKs (Android
/// only, DOCS-contracts-runtime §18): the `kartka/ext` channel to the
/// Kotlin host in `android/app/src/main/kotlin/com/kuhy/kartka/ext/`.
///
/// Calls and their argument / result maps are listed in §18; the typed
/// layer over them is `lib/sources/device_ext/`.
abstract interface class ExtensionRuntime {
  /// Runs [method] with [args]; throws [ExtensionRuntimeException] when the
  /// host or the extension fails.
  Future<Object?> invoke(String method, [Map<String, Object?> args]);

  /// Image bytes for one page or cover, fetched by the source's own client
  /// so its headers and interceptors (e.g. descrambling) apply.
  Future<Uint8List> image(
    String sourceId, {
    required int index,
    required String url,
    String? imageUrl,
  });
}

/// A failed [ExtensionRuntime] call, with the extension's own message.
class ExtensionRuntimeException implements Exception {
  /// Creates the error.
  const new(this.message);

  /// What the host or the extension reported.
  final String message;

  @override
  String toString() => message;
}

/// URL scheme of a page or cover served by an in-app extension.
const kartkaExtScheme = 'kartka-ext';

/// The [kartkaExtScheme] URL for image [index] of [sourceId]: [url] is the
/// Tachiyomi page URL, [imageUrl] the direct image URL when known.
String extImageUrl(
  String sourceId, {
  required int index,
  String url = '',
  String? imageUrl,
}) => Uri(
  scheme: kartkaExtScheme,
  host: 'source',
  pathSegments: [sourceId],
  queryParameters: {'i': '$index', 'u': url, 'img': ?imageUrl},
).toString();

/// Loads a [kartkaExtScheme] URL through [runtime].
Future<Uint8List> loadExtImage(ExtensionRuntime runtime, Uri uri) {
  final q = uri.queryParameters;
  return runtime.image(
    uri.pathSegments.single,
    index: int.parse(q['i'] ?? '0'),
    url: q['u'] ?? '',
    imageUrl: q['img'],
  );
}
