import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/browse/browse_scope.dart';
import 'package:kartka/browse/state/chapter_order.dart';
import 'package:kartka/browse/state/manga_detail_controller.dart';
import 'package:kartka/browse/state/read_state.dart';
import 'package:kartka/browse/ui/chapter_tile.dart';
import 'package:kartka/browse/ui/continue_fab.dart';
import 'package:kartka/browse/ui/detail_header.dart';
import 'package:kartka/browse/ui/detail_menu.dart';
import 'package:kartka/browse/ui/detail_status.dart';
import 'package:kartka/browse/ui/refresh_mark.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/ui/spoken_label.dart';

/// `/manga/:sourceId/:mangaUrl`: a compact header, then the chapter list
/// (newest first, or unread first) right away; "Continue" floats, every
/// other action is in the app bar's overflow menu.
class MangaDetailScreen extends StatefulWidget {
  /// Creates the screen for the manga at [mangaUrl] in [sourceId].
  const new({required this.sourceId, required this.mangaUrl, super.key});

  /// Decoded source id.
  final String sourceId;

  /// Decoded manga url.
  final String mangaUrl;

  @override
  State<MangaDetailScreen> createState() => _MangaDetailScreenState();
}

class _MangaDetailScreenState extends State<MangaDetailScreen> {
  MangaDetailController? _controller;
  late Stream<ReadMarks> _marks;
  late Stream<ReadingProgress?> _progress;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final deps = BrowseScope.of(context);
    final c = MangaDetailController(
      deps,
      sourceId: widget.sourceId,
      mangaUrl: widget.mangaUrl,
    );
    _controller = c;
    _marks = c.readMarks();
    _progress = c.progress();
    for (final slot in deps.detailSlots) {
      slot.opened(c.key);
    }
    unawaited(c.load());
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  /// Pull-to-refresh and the app-bar Refresh: re-fetch the chapter list,
  /// then say what changed.
  Future<void> _refresh() async {
    final outcome = await _controller!.refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: RefreshMark(outcome)));
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller!;
    final sort = BrowseScope.of(context).chapterSort;
    return ListenableBuilder(
      listenable: Listenable.merge([c, sort]),
      builder: (context, _) => StreamBuilder<ReadMarks>(
        stream: _marks,
        initialData: ReadMarks.none,
        builder: (context, snap) {
          final read = readUrls(c.chapters, snap.data!);
          final details = c.details;
          return Scaffold(
            appBar: AppBar(
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh, semanticLabel: 'Refresh'),
                  onPressed: () => unawaited(_refresh()),
                ),
                if (details != null)
                  DetailMenu(controller: c, details: details, read: read),
              ],
            ),
            floatingActionButton: details == null
                ? null
                : ContinueFab(controller: c, progress: _progress, read: read),
            body: details == null
                ? DetailStatus(c)
                : _list(
                    context,
                    c,
                    details,
                    snap.data!,
                    read,
                    unread: sort.value,
                  ),
          );
        },
      ),
    );
  }

  Widget _list(
    BuildContext context,
    MangaDetailController c,
    MangaDetails details,
    ReadMarks marks,
    Set<String> read, {
    required bool unread,
  }) {
    final banner = staleBanner(c);
    final canDownload = BrowseScope.of(context).downloads != null;
    final newestFirst = c.chapters.reversed.toList();
    final shown = unread ? unreadFirst(newestFirst, read) : newestFirst;
    final list = RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (banner != null) SliverToBoxAdapter(child: banner),
          SliverToBoxAdapter(child: DetailHeader(details: details)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: SpokenLabel(
                semanticLabel: '${c.chapters.length} chapters',
                child: ExcludeSemantics(
                  child: Row(
                    children: [
                      const Icon(Icons.format_list_numbered),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        '${c.chapters.length}',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SliverList.builder(
            itemCount: shown.length,
            itemBuilder: (_, i) => ChapterTile(
              controller: c,
              chapter: shown[i],
              read: read.contains(shown[i].url),
              pages: pagesRead(shown[i], marks),
              canDownload: canDownload,
            ),
          ),
          // Room under the last row, so the FAB never covers its buttons.
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl * 2)),
        ],
      ),
    );
    // Stale content is on screen while the network refreshes it.
    if (!c.loading) return list;
    return Stack(
      children: [
        list,
        const Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: LinearProgressIndicator(),
        ),
      ],
    );
  }
}
