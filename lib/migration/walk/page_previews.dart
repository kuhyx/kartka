import 'dart:typed_data';

import 'package:design_system/design_system.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/source/manga_source.dart';
import 'package:material_ui/material_ui.dart';

/// Loads one page image's bytes (normally `PageImageLoader.load`).
typedef PageBytes = Future<Uint8List> Function(PageRef page);

/// Pages a preview shows.
const int previewPages = 3;

/// The first [previewPages] pages of [chapterUrl] on [source], side by side,
/// so kuhy can see whether a candidate is the series he reads (audit
/// 53c9b0fa, gap 4c). A page that fails shows a broken-image icon.
class PagePreviews extends StatefulWidget {
  /// Previews [chapterUrl] through [loader].
  const new({
    required this.source,
    required this.chapterUrl,
    required this.loader,
    super.key,
  });

  /// Where the chapter is.
  final MangaSource source;

  /// The previewed chapter.
  final String chapterUrl;

  /// Page bytes.
  final PageBytes loader;

  @override
  State<PagePreviews> createState() => _PagePreviewsState();
}

class _PagePreviewsState extends State<PagePreviews> {
  // Each page's failure is caught at once (as null): a page future that
  // errors before its builder listens would escape as unhandled.
  late final Future<List<Future<Uint8List?>>> _pages = widget.source
      .pages(widget.chapterUrl)
      .then(
        (all) => [
          for (final p in all.take(previewPages))
            widget.loader(p).then<Uint8List?>((b) => b, onError: (_) => null),
        ],
      );

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 160,
    child: FutureBuilder(
      future: _pages,
      builder: (context, snap) => Row(
        spacing: AppSpacing.xs,
        children: [
          if (snap.hasError) _broken(),
          for (final bytes in snap.data ?? const <Future<Uint8List?>>[])
            Expanded(child: _Page(bytes)),
        ],
      ),
    ),
  );
}

Widget _broken() =>
    const Icon(Icons.broken_image_outlined, semanticLabel: 'Page failed');

class _Page extends StatelessWidget {
  const new(this.bytes);

  final Future<Uint8List?> bytes;

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: bytes,
    builder: (context, snap) => switch (snap) {
      AsyncSnapshot(:final data?) => Image.memory(data, fit: BoxFit.contain),
      AsyncSnapshot(connectionState: ConnectionState.done) => Center(
        child: _broken(),
      ),
      _ => const SizedBox.shrink(),
    },
  );
}
