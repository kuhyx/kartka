import 'package:flutter/material.dart';
import 'package:kartka/app/cached_cover.dart';
import 'package:kartka/browse/browse_scope.dart';

/// A manga cover loaded through [BrowseDeps.coverLoader]; a neutral
/// placeholder while loading, on failure, or when there is no cover.
class CoverImage extends StatelessWidget {
  /// Creates a cover for [url].
  const new(this.url, {super.key});

  /// Cover url, or null for none.
  final String? url;

  @override
  Widget build(BuildContext context) =>
      CachedCover(url: url, loader: BrowseScope.of(context).coverLoader);
}
