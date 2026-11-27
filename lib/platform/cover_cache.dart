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
  new({
    required this.load,
    this.store,
    this.maxBytes = 48 << 20,
    this.maxLoads = 2,
    this.maxHold = const Duration(seconds: 3),
    this.releaseGrace = const Duration(milliseconds: 250),
  });

  /// Fetches a cover the cache does not have.
  final Future<Uint8List> Function(String url) load;

  /// Where covers persist across launches (`KartkaPlatform.cache`).
  final BlobStore? store;

  /// Encoded bytes kept in memory before the least recent are dropped.
  final int maxBytes;

  /// Network loads per host at once; the rest wait, newest first.
  ///
  /// A grid of uncached covers sent all at once filled the source's rate
  /// limiter on the server (50 MangaFire thumbnails: up to 25 s each), and
  /// the next browse page queued behind them for up to 41 s (89e1ec6e).
  /// The limiter's throughput is the same either way; capped, a page waits
  /// behind at most this many covers, and the covers just scrolled to go
  /// first.
  final int maxLoads;

  /// How long [yieldTo] holds back un-started covers at most.
  final Duration maxHold;

  /// How long covers stay held after the last [yieldTo] settles, so the
  /// grid's next page (asked for 30-60 ms later) does not start behind
  /// covers released in between (1.7 s instead of 0.7 s, 89e1ec6e).
  final Duration releaseGrace;

  /// Key prefix in [store].
  static const prefix = 'cache/covers/';

  final _memory = <String, Uint8List>{}; // Insertion-ordered: LRU.
  final _inFlight = <String, Future<Uint8List>>{};
  final _running = <String, int>{};
  final _waiting = <String, List<Completer<void>>>{};
  int _bytes = 0;
  int _yields = 0;
  Timer? _grace; // Running: covers stay held ([releaseGrace]).

  bool get _held => _yields > 0 || _grace != null;

  /// Holds back cover loads that have not started while [work] (a browse
  /// page fetch) runs, at most [maxHold], so the page is not queued
  /// behind covers on the server's rate limiter (89e1ec6e). Covers
  /// already loading finish; the held ones then start, newest first.
  void yieldTo(Future<Object?> work) {
    _yields++;
    _grace?.cancel();
    _grace = null;
    var settled = false;
    late final Timer expiry;
    void done() {
      if (settled) return;
      settled = true;
      // A settled page leaves no timer behind (widget tests assert that).
      expiry.cancel();
      _yields--;
      if (_yields > 0) return;
      if (releaseGrace == Duration.zero) return _startWaiting();
      _grace = Timer(releaseGrace, () {
        _grace = null;
        _startWaiting();
      });
    }

    expiry = Timer(maxHold, done);
    work.then<void>((_) => done(), onError: (Object _) => done()).ignore();
  }

  /// When every yield is over, start waiting covers of every host up to
  /// [maxLoads] each, newest first.
  void _startWaiting() {
    for (final host in _waiting.keys.toList()) {
      final waiting = _waiting[host];
      if (waiting == null) continue;
      var free = maxLoads - (_running[host] ?? 0);
      while (free > 0 && waiting.isNotEmpty) {
        waiting.removeLast().complete();
        _running[host] = (_running[host] ?? 0) + 1;
        free--;
      }
      if (waiting.isEmpty) _waiting.remove(host);
    }
  }

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
    final bytes = key == null ? await load(url) : await _slotted(url);
    // A challenge page served as 200 must not outlive this launch.
    if (key != null && looksLikeImage(bytes)) unawaited(_write(key, bytes));
    return _remember(url, bytes);
  }

  /// [load] of [url] once its host has a free slot and no page fetch
  /// holds covers back ([yieldTo]).
  Future<Uint8List> _slotted(String url) async {
    final host = Uri.tryParse(url)?.host ?? '';
    if (_held || (_running[host] ?? 0) >= maxLoads) {
      // Whoever completes the turn has already counted this slot.
      final turn = Completer<void>();
      (_waiting[host] ??= []).add(turn);
      await turn.future;
    } else {
      _running[host] = (_running[host] ?? 0) + 1;
    }
    try {
      return await load(url);
    } finally {
      // The slot passes to the newest waiting cover, or frees (always
      // frees while a page fetch holds covers back).
      final waiting = _waiting[host];
      if (!_held && waiting != null && waiting.isNotEmpty) {
        waiting.removeLast().complete();
      } else {
        _running[host] = _running[host]! - 1;
      }
    }
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
