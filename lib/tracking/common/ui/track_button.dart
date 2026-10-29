import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/core/models/manga_key.dart';
import 'package:kartka/tracking/common/track_binding.dart';
import 'package:kartka/tracking/common/tracking_service.dart';
import 'package:kartka/tracking/common/ui/tracker_section.dart';

/// The manga-detail action: shows whether [mangaKey] is tracked and opens
/// the track sheet. (The pull of remote progress on opening the detail
/// screen is `TrackingDetailSlot.opened`.)
class TrackButton extends StatefulWidget {
  /// Creates the button.
  const new({
    required this.service,
    required this.mangaKey,
    required this.title,
    super.key,
  });

  /// Tracking state.
  final TrackingService service;

  /// The manga on the detail screen.
  final MangaKey mangaKey;

  /// Its title, the default search query.
  final String title;

  @override
  State<TrackButton> createState() => _TrackButtonState();
}

class _TrackButtonState extends State<TrackButton> {
  late final Stream<List<TrackBinding>> _bindings = widget.service
      .watchBindings(widget.mangaKey);

  @override
  Widget build(BuildContext context) => StreamBuilder<List<TrackBinding>>(
    stream: _bindings,
    builder: (context, snap) {
      final tracked = snap.data?.isNotEmpty ?? false;
      return OutlinedButton.icon(
        icon: Icon(tracked ? Icons.check : Icons.sync),
        label: Text(tracked ? 'Tracking' : 'Track'),
        onPressed: () => unawaited(
          showTrackSheet(
            context,
            service: widget.service,
            mangaKey: widget.mangaKey,
            title: widget.title,
          ),
        ),
      );
    },
  );
}

/// Opens the track sheet for [mangaKey]. `Escape` closes it.
Future<void> showTrackSheet(
  BuildContext context, {
  required TrackingService service,
  required MangaKey mangaKey,
  required String title,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (context) => SafeArea(
    child: ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text('Tracking', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpacing.sm),
        if (service.trackers.isEmpty) const Text('No trackers installed'),
        for (final t in service.trackers)
          TrackerSection(
            service: service,
            tracker: t,
            mangaKey: mangaKey,
            title: title,
          ),
      ],
    ),
  ),
);
