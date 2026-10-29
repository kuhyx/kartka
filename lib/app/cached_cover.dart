import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Loads cover bytes for a url (normally `CoverCache.get`).
typedef CoverBytes = Future<Uint8List> Function(String url);

/// A manga cover, or a neutral placeholder while loading, on failure, or
/// when there is no url or loader. Shared by the Library and Browse grids.
///
/// A loader that answers synchronously (a `CoverCache` memory hit) draws
/// the cover on the first frame: a remounted tile never flashes the
/// placeholder. The cover is decoded at the tile's width in device pixels
/// (rounded up to [widthBucket]), not at the image's full size.
class CachedCover extends StatefulWidget {
  /// A cover for [url] loaded with [loader].
  const new({required this.url, required this.loader, super.key});

  /// Cover url.
  final String? url;

  /// Byte loader.
  final CoverBytes? loader;

  /// Decode widths are multiples of this, so a small layout change reuses
  /// the decoded image.
  static const widthBucket = 64;

  @override
  State<CachedCover> createState() => _CachedCoverState();
}

class _CachedCoverState extends State<CachedCover> {
  Uint8List? _bytes;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(CachedCover old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url || old.loader != widget.loader) _resolve();
  }

  void _resolve() {
    final id = ++_request;
    _bytes = null;
    final url = widget.url;
    final loader = widget.loader;
    if (url == null || loader == null) return;
    var sync = true;
    loader(url).then<void>(
      (bytes) {
        if (id != _request) return;
        if (sync) {
          _bytes = bytes; // Synchronous hit: this frame draws it.
        } else if (mounted) {
          setState(() => _bytes = bytes);
        }
      },
      onError: (Object _) {}, // Stays a placeholder.
    ).ignore();
    sync = false;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(
        child: Icon(Icons.menu_book_outlined, color: scheme.onSurfaceVariant),
      ),
    );
    final bytes = _bytes;
    if (bytes == null) return placeholder;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, box) => Image(
        image: ResizeImage.resizeIfNeeded(
          _decodeWidth(box.maxWidth * dpr),
          null,
          MemoryImage(bytes),
        ),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => placeholder,
      ),
    );
  }

  /// [pixels] rounded up to the bucket; null (full size) when unbounded.
  static int? _decodeWidth(double pixels) {
    if (!pixels.isFinite || pixels <= 0) return null;
    const b = CachedCover.widthBucket;
    return (pixels / b).ceil() * b;
  }
}
