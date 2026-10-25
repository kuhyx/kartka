import 'dart:typed_data';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/core/redact.dart';

/// One page image, with loading and retryable error states.
class ReaderPageImage extends StatelessWidget {
  /// Shows the image in [bytes] for 1-based [pageNumber].
  const new({
    required this.bytes,
    required this.pageNumber,
    required this.onRetry,
    this.fitWidth = false,
    super.key,
  });

  /// The encoded image, usually from the page cache.
  final Future<Uint8List> bytes;

  /// The page number shown while loading.
  final int pageNumber;

  /// Refetches after an error.
  final VoidCallback onRetry;

  /// Whether to fill the width (webtoon) instead of fitting the viewport.
  final bool fitWidth;

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: bytes,
    builder: (context, snap) {
      final error = snap.error;
      if (error != null) return _failed(context, redactUrlQueries('$error'));
      final data = snap.data;
      if (data == null) return _loading(context);
      return Image.memory(
        data,
        fit: fitWidth ? BoxFit.fitWidth : BoxFit.contain,
        width: fitWidth ? double.infinity : null,
        gaplessPlayback: true,
        errorBuilder: (context, e, _) =>
            _failed(context, redactUrlQueries('$e')),
      );
    },
  );

  Widget _placeholder({required Widget child}) => AspectRatio(
    aspectRatio: fitWidth ? 0.7 : 1,
    child: Center(child: child),
  );

  Widget _loading(BuildContext context) => _placeholder(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: AppSpacing.sm),
        Text('$pageNumber', style: Theme.of(context).textTheme.labelLarge),
      ],
    ),
  );

  Widget _failed(BuildContext context, String message) => _placeholder(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Page $pageNumber failed: $message',
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}
