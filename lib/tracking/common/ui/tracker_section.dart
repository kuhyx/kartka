import 'dart:async';

import 'package:collection/collection.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/core/models/manga_key.dart';
import 'package:kartka/core/redact.dart';
import 'package:kartka/core/ui/spoken_label.dart';
import 'package:kartka/tracking/common/credentials_login.dart';
import 'package:kartka/tracking/common/track_binding.dart';
import 'package:kartka/tracking/common/tracker.dart';
import 'package:kartka/tracking/common/tracking_service.dart';
import 'package:kartka/tracking/common/ui/track_search.dart';

/// One-line summary of a remote list entry, spoken only: [TrackStatusRow]
/// paints it as glyphs and numbers.
String formatStatus(TrackStatus? s) {
  if (s == null) return 'Not on your list yet';
  final total = s.totalChapters;
  final count = total == null
      ? '${s.chaptersRead}'
      : '${s.chaptersRead} / $total';
  final score = s.score;
  return [
    s.status,
    '$count chapters',
    if (score != null) 'score $score',
  ].join(' · ');
}

/// A remote list entry as the tracker's own status word, a chapter count
/// and a score, each behind a glyph; the whole row speaks [formatStatus].
class TrackStatusRow extends StatelessWidget {
  /// Paints [status]; null means not on the remote list yet.
  const new(this.status, {super.key});

  /// The remote entry, or null.
  final TrackStatus? status;

  @override
  Widget build(BuildContext context) {
    final s = status;
    if (s == null) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: Icon(Icons.playlist_add, semanticLabel: formatStatus(null)),
      );
    }
    final total = s.totalChapters;
    final score = s.score;
    return SpokenLabel(
      semanticLabel: formatStatus(s),
      child: ExcludeSemantics(
        child: Wrap(
          spacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(s.status),
            const Icon(Icons.layers_outlined, size: 16),
            Text(
              total == null ? '${s.chaptersRead}' : '${s.chaptersRead}/$total',
            ),
            if (score != null) ...[
              const Icon(Icons.star_outline, size: 16),
              Text('$score'),
            ],
          ],
        ),
      ),
    );
  }
}

/// One tracker in the track sheet: login, search-and-bind, or the bound
/// entry's remote status with unbind.
class TrackerSection extends StatefulWidget {
  /// Creates the section.
  const new({
    required this.service,
    required this.tracker,
    required this.mangaKey,
    required this.title,
    super.key,
  });

  /// Tracking state.
  final TrackingService service;

  /// The tracker shown.
  final Tracker tracker;

  /// The manga being tracked.
  final MangaKey mangaKey;

  /// Default search query.
  final String title;

  @override
  State<TrackerSection> createState() => _TrackerSectionState();
}

class _TrackerSectionState extends State<TrackerSection> {
  late Future<bool> _loggedIn = widget.tracker.isLoggedIn();
  late final Stream<List<TrackBinding>> _bindings = widget.service
      .watchBindings(widget.mangaKey);

  Tracker get _t => widget.tracker;

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } on Object catch (e) {
      if (mounted) showError(context, redactUrlQueries('${_t.name}: $e'));
    }
    if (!mounted) return;
    setState(() {
      _loggedIn = _t.isLoggedIn();
    });
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
    child: FutureBuilder<bool>(
      future: _loggedIn,
      builder: (context, login) => StreamBuilder<List<TrackBinding>>(
        stream: _bindings,
        builder: (context, snap) {
          final binding = snap.data?.firstWhereOrNull(
            (b) => b.service == _t.id,
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context, loggedIn: login.data ?? false),
              if (login.data ?? false) _body(binding),
            ],
          );
        },
      ),
    ),
  );

  /// Credential trackers bring their own sheet; OAuth ones redirect.
  Future<void> _login(BuildContext context) {
    final t = _t;
    return t is CredentialsLogin
        ? (t as CredentialsLogin).showLogin(context)
        : t.login();
  }

  Widget _header(BuildContext context, {required bool loggedIn}) => Row(
    children: [
      Expanded(
        child: Text(_t.name, style: Theme.of(context).textTheme.titleMedium),
      ),
      if (loggedIn)
        IconButton(
          style: _button,
          onPressed: () => unawaited(_guard(_t.logout)),
          icon: const Icon(Icons.logout, semanticLabel: 'Log out'),
        )
      else
        IconButton.filled(
          style: _button,
          onPressed: () => unawaited(_guard(() => _login(context))),
          icon: Icon(Icons.login, semanticLabel: 'Log in to ${_t.name}'),
        ),
    ],
  );

  Widget _body(TrackBinding? binding) {
    if (binding == null) {
      return TrackSearch(
        tracker: _t,
        initialQuery: widget.title,
        onPick: (hit) => _guard(
          () => widget.service.bind(widget.mangaKey, _t.id, hit.remoteId),
        ),
      );
    }
    return Row(
      children: [
        Expanded(
          child: FutureBuilder<TrackStatus?>(
            key: ValueKey(binding),
            future: _t.fetch(binding.remoteId),
            builder: (context, s) => s.connectionState != ConnectionState.done
                ? const LinearProgressIndicator()
                : s.hasError
                ? Text('${s.error}')
                : TrackStatusRow(s.data),
          ),
        ),
        IconButton(
          style: _button,
          onPressed: () => unawaited(
            _guard(() => widget.service.unbind(widget.mangaKey, _t.id)),
          ),
          icon: const Icon(Icons.link_off, semanticLabel: 'Unbind'),
        ),
      ],
    );
  }

  static final ButtonStyle _button = IconButton.styleFrom(
    minimumSize: const Size.square(48),
  );
}
