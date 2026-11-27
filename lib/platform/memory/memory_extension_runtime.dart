import 'dart:typed_data';

import 'package:kartka/platform/extension_runtime.dart';

/// In-memory [ExtensionRuntime] for tests: every call is recorded and
/// answered by its handler; images by [images].
class FakeExtensionRuntime implements ExtensionRuntime {
  /// Answers with `handler` (default: an empty inventory for `init` /
  /// `installed`, null otherwise).
  new({
    Object? Function(String method, Map<String, Object?> args)? handler,
    this.images = const {},
  }) : _handler = handler ?? _empty;

  static Object? _empty(String method, Map<String, Object?> _) =>
      method == 'init' || method == 'installed'
      ? const {'installed': <Object?>[], 'failed': <Object?, Object?>{}}
      : null;

  final Object? Function(String, Map<String, Object?>) _handler;

  /// Image bytes by direct image URL (or page URL when it has none).
  final Map<String, Uint8List> images;

  /// Every call so far: method name and arguments.
  final List<(String, Map<String, Object?>)> calls = [];

  @override
  Future<Object?> invoke(
    String method, [
    Map<String, Object?> args = const {},
  ]) async {
    calls.add((method, args));
    return _handler(method, args);
  }

  @override
  Future<void> cancelBackground() => invoke('cancelBackground');

  @override
  Future<Uint8List> image(
    String sourceId, {
    required int index,
    required String url,
    String? imageUrl,
  }) async {
    calls.add(('image', {'id': sourceId, 'index': index, 'url': url}));
    final bytes = images[imageUrl ?? url];
    if (bytes == null) throw ExtensionRuntimeException('no image $url');
    return bytes;
  }
}
