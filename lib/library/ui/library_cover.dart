import 'package:flutter/material.dart';
import 'package:kartka/app/cached_cover.dart';
import 'package:kartka/library/state/library_deps.dart';

/// A cover image, or a neutral placeholder while loading, on failure, or
/// when there is no url or loader ([CachedCover]: decoded at tile size and
/// drawn at once when the loader's cache has it).
class LibraryCover extends StatelessWidget {
  /// Creates a cover for [url] loaded with [loader].
  const new({required this.url, required this.loader, super.key});

  /// Cover url.
  final String? url;

  /// Byte loader (network or offline blob).
  final CoverLoader? loader;

  @override
  Widget build(BuildContext context) => CachedCover(url: url, loader: loader);
}
