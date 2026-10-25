import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/browse/browse_scope.dart';
import 'package:kartka/browse/state/manga_detail_controller.dart';
import 'package:kartka/browse/state/read_state.dart';
import 'package:kartka/browse/ui/challenge_prompt.dart';
import 'package:kartka/browse/ui/chapter_tile.dart';
import 'package:kartka/browse/ui/detail_header.dart';
import 'package:kartka/core/redact.dart';
import 'package:kartka/core/source/challenge.dart';

/// `/manga/:sourceId/:mangaUrl`: header, actions and the chapter list
/// (newest first, as sources and readers expect).
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
  Stream<ReadMarks>? _marks;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final c = MangaDetailController(
      BrowseScope.of(context),
      sourceId: widget.sourceId,
      mangaUrl: widget.mangaUrl,
    );
    _controller = c;
    _marks = c.readMarks();
    unawaited(c.load());
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller!;
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => unawaited(c.load()),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: c,
        builder: (context, _) => _body(context, c),
      ),
    );
  }

  Widget _body(BuildContext context, MangaDetailController c) {
    final details = c.details;
    if (details == null) {
      if (c.error != null) {
        final retry = FilledButton(
          onPressed: () => unawaited(c.load()),
          child: const Text('Retry'),
        );
        if (c.error case final ChallengeRequired challenge) {
          return Center(
            child: ChallengePrompt(
              challenge,
              onRetry: () => unawaited(c.load()),
            ),
          );
        }
        if (c.error is SourceUnavailable) {
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              EmptyState(
                icon: Icons.cloud_off_outlined,
                title: 'Source unavailable',
                message:
                    'No installed source provides ${c.sourceId}. Install '
                    'its plugin or check the Suwayomi server.',
              ),
              retry,
            ],
          );
        }
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                redactUrlQueries('Could not load: ${c.error}'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              retry,
            ],
          ),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    final canDownload = BrowseScope.of(context).downloads != null;
    final newestFirst = c.chapters.reversed.toList();
    return StreamBuilder<ReadMarks>(
      stream: _marks,
      initialData: ReadMarks.none,
      builder: (context, snap) {
        final read = readUrls(c.chapters, snap.data!);
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: DetailHeader(controller: c, details: details, read: read),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Text(
                  '${c.chapters.length} chapters',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            SliverList.builder(
              itemCount: newestFirst.length,
              itemBuilder: (_, i) => ChapterTile(
                controller: c,
                chapter: newestFirst[i],
                read: read.contains(newestFirst[i].url),
                canDownload: canDownload,
              ),
            ),
          ],
        );
      },
    );
  }
}
