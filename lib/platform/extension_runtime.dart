import 'dart:async';
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

  /// Cancels every background call in flight ([runAsBackground]); each
  /// throws [ExtensionCallCancelled]. Sent when a shown page starts
  /// loading: downloads beside an open made its page list and page 1 take
  /// 1 s each instead of 0.2 s (64f0bd6f).
  Future<void> cancelBackground();
}

/// A background call the host cancelled for a shown page: not a failure,
/// the caller runs it again once the shown page is in.
class ExtensionCallCancelled extends ExtensionRuntimeException {
  /// Creates the error.
  const new() : super('cancelled');
}

final _background = Object();

/// Runs [body] as background work (a download): its [ExtensionRuntime]
/// calls are marked so [ExtensionRuntime.cancelBackground] can stop them.
T runAsBackground<T>(T Function() body) =>
    runZoned(body, zoneValues: {_background: true});

/// Whether the current code runs inside [runAsBackground].
bool get isBackgroundCall => Zone.current[_background] == true;

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
