import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:kartka/browse/browse_scope.dart';

/// A manga cover loaded through [BrowseDeps.coverLoader]; a neutral
/// placeholder while loading, on failure, or when there is no cover.
class CoverImage extends StatefulWidget {
  /// Creates a cover for [url].
  const CoverImage(this.url, {super.key});

  /// Cover url, or null for none.
  final String? url;

  @override
  State<CoverImage> createState() => _CoverImageState();
}

class _CoverImageState extends State<CoverImage> {
  Future<Uint8List>? _bytes;
  String? _loadedUrl;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(CoverImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _resolve();
  }

  void _resolve() {
    final url = widget.url;
    if (url == _loadedUrl && _bytes != null) return;
    final loader = BrowseScope.of(context).coverLoader;
    _loadedUrl = url;
    _bytes = url == null || loader == null ? null : loader(url);
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.menu_book_outlined,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
    final bytes = _bytes;
    if (bytes == null) return placeholder;
    return FutureBuilder<Uint8List>(
      future: bytes,
      builder: (context, snap) => snap.hasData
          ? Image.memory(
              snap.data!,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => placeholder,
            )
          : placeholder,
    );
  }
}
