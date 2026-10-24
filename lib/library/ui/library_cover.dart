import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:kartka/library/state/library_deps.dart';

/// A cover image, or a neutral placeholder while loading, on failure, or
/// when there is no url or loader.
class LibraryCover extends StatefulWidget {
  /// Creates a cover for [url] loaded with [loader].
  const new({required this.url, required this.loader, super.key});

  /// Cover url.
  final String? url;

  /// Byte loader (network or offline blob).
  final CoverLoader? loader;

  @override
  State<LibraryCover> createState() => _LibraryCoverState();
}

class _LibraryCoverState extends State<LibraryCover> {
  Future<Uint8List>? _bytes;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(LibraryCover old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url || old.loader != widget.loader) _resolve();
  }

  void _resolve() {
    final url = widget.url;
    final loader = widget.loader;
    _bytes = url == null || loader == null ? null : loader(url);
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
