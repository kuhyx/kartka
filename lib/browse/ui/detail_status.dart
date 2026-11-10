import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/browse/state/manga_detail_controller.dart';
import 'package:kartka/browse/ui/challenge_prompt.dart';
import 'package:kartka/core/redact.dart';
import 'package:kartka/core/source/challenge.dart';
import 'package:kartka/core/ui/spoken_label.dart';

/// The detail screen before details exist: a spinner while loading, else
/// the failure (a challenge prompt, "Source unavailable", or the redacted
/// error) with Retry. Over shown (stored) details, [staleBanner] instead.
class DetailStatus extends StatelessWidget {
  /// Creates the status view of [controller].
  const new(this.controller, {super.key});

  /// Detail state (its [MangaDetailController.error]).
  final MangaDetailController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final error = c.error;
    if (error == null) return const Center(child: CircularProgressIndicator());
    final retry = _retry(c);
    if (error case final ChallengeRequired challenge) {
      return Center(
        child: ChallengePrompt(challenge, onRetry: () => unawaited(c.load())),
      );
    }
    if (error is SourceUnavailable) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [_unavailable(c), retry],
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, semanticLabel: 'Could not load'),
          Text(redactUrlQueries('$error'), textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.sm),
          retry,
        ],
      ),
    );
  }
}

/// Above stored (stale) content: the failures the user can act on, which
/// would otherwise hide behind the saved data. Null for any other state;
/// other refresh errors are reported by the refresh snackbar.
Widget? staleBanner(MangaDetailController c) => switch (c.error) {
  final ChallengeRequired challenge => Padding(
    padding: const EdgeInsets.all(AppSpacing.md),
    child: ChallengePrompt(challenge, onRetry: () => unawaited(c.load())),
  ),
  SourceUnavailable() => Column(children: [_unavailable(c), _retry(c)]),
  _ => null,
};

Widget _retry(MangaDetailController c) => IconButton(
  iconSize: 32,
  onPressed: () => unawaited(c.load()),
  icon: const Icon(Icons.refresh, semanticLabel: 'Retry'),
);

/// The source id is data (which plugin to install), so it stays painted.
Widget _unavailable(MangaDetailController c) => Column(
  mainAxisSize: MainAxisSize.min,
  children: [
    const EmptyMark(
      icon: Icons.cloud_off_outlined,
      semanticLabel: 'Source unavailable',
    ),
    Text(c.sourceId),
  ],
);
