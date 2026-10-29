import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:kartka/platform/blob_store.dart';
import 'package:kartka/platform/page_image.dart';

/// Cover image bytes: a memory LRU, then a persistent [BlobStore], then
/// [load] (the network), with concurrent requests for one URL sharing a
/// single load.
///
/// Covers were fetched on every mount: a category switch or scrolling back
/// blanked them for 0.5-1 s. Now a remount finds them in memory, where
/// [get] answers with a [SynchronousFuture] so the cover is drawn on the
/// widget's first frame. The same `Uint8List` is returned for a URL every
/// time, so the image cache (keyed on the bytes' identity) reuses the
/// decoded image too. Offline covers (`kartka-blob://`) are already local
/// and are kept in memory only.
class CoverCache {
  /// A cache over [load], persisting into [store] (none: memory only).
  new({required this.load, this.store, this.maxBytes = 48 << 20});

  /// Fetches a cover the cache does not have.
  final Future<Uint8List> Function(String url) load;

  /// Where covers persist across launches (`KartkaPlatform.cache`).
  final BlobStore? store;

  /// Encoded bytes kept in memory before the least recent are dropped.
  final int maxBytes;

  /// Key prefix in [store].
  static const prefix = 'cache/covers/';

  final _memory = <String, Uint8List>{}; // Insertion-ordered: LRU.
  final _inFlight = <String, Future<Uint8List>>{};
  int _bytes = 0;

  /// The cover of [url] when it is in memory (marking it recent), else null.
  Uint8List? peek(String url) {
    final hit = _memory.remove(url);
    if (hit != null) _memory[url] = hit;
    return hit;
  }

  /// The cover of [url]: synchronous from memory, else from [store] or
  /// [load]. A failure is not cached; the next call tries again.
  Future<Uint8List> get(String url) {
    final hit = peek(url);
    if (hit != null) return SynchronousFuture(hit);
    // A block body: returning the removed future would make whenComplete
    // wait for itself.
    return _inFlight[url] ??= _fetch(url).whenComplete(() {
      unawaited(_inFlight.remove(url));
    });
  }

  Future<Uint8List> _fetch(String url) async {
    final key = url.startsWith('$kartkaBlobScheme://')
        ? null
        : '$prefix${sha1.convert(utf8.encode(url))}';
    if (key != null) {
      final stored = await _read(key);
      if (stored != null) return _remember(url, stored);
    }
    final bytes = await load(url);
    // A challenge page served as 200 must not outlive this launch.
    if (key != null && looksLikeImage(bytes)) unawaited(_write(key, bytes));
    return _remember(url, bytes);
  }

  /// A store that fails costs only the persistence, never the cover.
  Future<Uint8List?> _read(String key) async {
    try {
      return await store?.get(key);
    } on Object {
      return null;
    }
  }

  Future<void> _write(String key, Uint8List bytes) async {
    try {
      await store?.put(key, bytes);
    } on Object {
      // Not persisted; the next launch fetches it again.
    }
  }

  Uint8List _remember(String url, Uint8List bytes) {
    _memory[url] = bytes;
    _bytes += bytes.length;
    while (_bytes > maxBytes && _memory.length > 1) {
      final oldest = _memory.keys.first;
      _bytes -= _memory.remove(oldest)!.length;
    }
    return bytes;
  }
}

/// Whether [b] starts like a JPEG, PNG, GIF, WebP or AVIF/HEIF image.
bool looksLikeImage(Uint8List b) {
  bool at(int i, List<int> magic) {
    if (b.length < i + magic.length) return false;
    for (var k = 0; k < magic.length; k++) {
      if (b[i + k] != magic[k]) return false;
    }
    return true;
  }

  return at(0, const [0xFF, 0xD8, 0xFF]) ||
      at(0, const [0x89, 0x50, 0x4E, 0x47]) ||
      at(0, ascii.encode('GIF8')) ||
      (at(0, ascii.encode('RIFF')) && at(8, ascii.encode('WEBP'))) ||
      at(4, ascii.encode('ftyp'));
}
