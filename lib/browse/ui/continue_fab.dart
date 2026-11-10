import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kartka/app/routes.dart';
import 'package:kartka/browse/state/chapter_order.dart';
import 'package:kartka/browse/state/manga_detail_controller.dart';
import 'package:kartka/core/models/models.dart';

/// The detail screen's floating "Continue": opens the progress chapter, or
/// the first unread one when there is no progress yet. Absent only when the
/// manga has no chapters at all.
class ContinueFab extends StatelessWidget {
  /// Creates the button; [progress] is the controller's live progress.
  const new({
    required this.controller,
    required this.progress,
    required this.read,
    super.key,
  });

  /// Detail state.
  final MangaDetailController controller;

  /// Live reading progress of the manga.
  final Stream<ReadingProgress?> progress;

  /// Read chapter urls.
  final Set<String> read;

  @override
  Widget build(BuildContext context) => StreamBuilder<ReadingProgress?>(
    stream: progress,
    builder: (context, snap) {
      final target =
          snap.data?.chapterUrl ?? firstUnread(controller.chapters, read)?.url;
      if (target == null) return const SizedBox.shrink();
      return FloatingActionButton(
        key: const ValueKey('continue'),
        onPressed: () => unawaited(
          context.push(
            readRoute(controller.sourceId, controller.mangaUrl, target),
          ),
        ),
        child: const Icon(Icons.play_arrow, semanticLabel: 'Continue'),
      );
    },
  );
}
