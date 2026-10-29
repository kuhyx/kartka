import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/browse/state/manga_detail_controller.dart';
import 'package:kartka/browse/ui/challenge_prompt.dart';
import 'package:kartka/core/redact.dart';
import 'package:kartka/core/source/challenge.dart';

/// The detail screen before details exist: a spinner while loading, else
/// the failure (a challenge prompt, "Source unavailable", or the redacted
/// error) with Retry.
class DetailStatus extends StatelessWidget {
  /// Creates the status view of [controller].
  const new(this.controller, {super.key});

  /// Detail state.
  final MangaDetailController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final error = c.error;
    if (error == null) return const Center(child: CircularProgressIndicator());
    final retry = FilledButton(
      onPressed: () => unawaited(c.load()),
      child: const Text('Retry'),
    );
    if (error case final ChallengeRequired challenge) {
      return Center(
        child: ChallengePrompt(challenge, onRetry: () => unawaited(c.load())),
      );
    }
    if (error is SourceUnavailable) {
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
            redactUrlQueries('Could not load: $error'),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          retry,
        ],
      ),
    );
  }
}
