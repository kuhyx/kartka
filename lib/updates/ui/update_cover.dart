import 'dart:typed_data';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/updates/state/updates_deps.dart';

/// Thumbnail width of a manga heading's cover.
const updateCoverWidth = 40.0;

/// Thumbnail size of a manga heading's cover (2:3).
const updateCoverSize = Size(updateCoverWidth, updateCoverWidth * 1.5);

/// A small cover, decoded at its displayed size (`cacheWidth`), or a
/// placeholder while loading, on failure, or without a url or loader.
class UpdateCover extends StatefulWidget {
  /// Creates the thumbnail of [url].
  const new({required this.url, required this.loader, super.key});

  /// Cover url.
  final String? url;

  /// Byte loader.
  final CoverBytes? loader;

  @override
  State<UpdateCover> createState() => _UpdateCoverState();
}

class _UpdateCoverState extends State<UpdateCover> {
  // Loaded once per url, never in build; a recycled row with another url
  // loads again.
  Future<Uint8List>? _bytes;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(UpdateCover old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _resolve();
  }

  void _resolve() => _bytes = switch ((widget.url, widget.loader)) {
    (final String url, final CoverBytes load) => load(url),
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Icon(Icons.menu_book_outlined, color: scheme.onSurfaceVariant),
    );
    final bytes = _bytes;
    final cacheWidth =
        (updateCoverSize.width * MediaQuery.devicePixelRatioOf(context))
            .round();
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: SizedBox.fromSize(
        size: updateCoverSize,
        child: bytes == null
            ? placeholder
            : FutureBuilder<Uint8List>(
                future: bytes,
                builder: (context, snap) => snap.hasData
                    ? Image.memory(
                        snap.data!,
                        fit: BoxFit.cover,
                        cacheWidth: cacheWidth,
                        errorBuilder: (_, _, _) => placeholder,
                      )
                    : placeholder,
              ),
      ),
    );
  }
}
