import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

/// Decodes [provider] into the image cache ahead of display.
typedef PagePrecache = Future<void> Function(
  ImageProvider provider,
  BuildContext context,
);

/// [precacheImage] with decode errors left to the page that shows them
/// (it renders its own retry), instead of reported as framework errors.
Future<void> precacheQuietly(ImageProvider provider, BuildContext context) =>
    precacheImage(provider, context, onError: (_, _) {});

/// The decode width of a reader page: the screen's physical width, or twice
/// that while the page is [zoomed] (a double-tap zoom stays sharp).
///
/// Pages decoded at full size (often 2-4x the screen) cost 100-200 ms frames
/// to decode and upload on a phone, and a decode at twice the width is four
/// times the pixels, so only a zoomed page pays for it. Never upscaled: a
/// smaller page keeps its own size.
int readerDecodeWidth(BuildContext context, {bool zoomed = false}) => math.max(
  1,
  (MediaQuery.sizeOf(context).width *
          MediaQuery.devicePixelRatioOf(context) *
          (zoomed ? 2 : 1))
      .round(),
);

/// The one provider for page [bytes]: the reader's widgets and its
/// precache must build equal ones, or the precache decodes in vain.
ImageProvider readerPageProvider(Uint8List bytes, int width) => ResizeImage(
  MemoryImage(bytes),
  width: width,
  policy: ResizeImagePolicy.fit,
);
