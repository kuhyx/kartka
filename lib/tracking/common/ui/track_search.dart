import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/core/redact.dart';
import 'package:kartka/core/ui/spoken_label.dart';
import 'package:kartka/tracking/common/tracker.dart';

/// Search field plus results; picking a hit binds it. `Enter` searches.
class TrackSearch extends StatefulWidget {
  /// Creates the search.
  const new({
    required this.tracker,
    required this.initialQuery,
    required this.onPick,
    super.key,
  });

  /// Where to search.
  final Tracker tracker;

  /// Pre-filled query (the manga title).
  final String initialQuery;

  /// Called with the chosen hit.
  final Future<void> Function(TrackSearchResult hit) onPick;

  @override
  State<TrackSearch> createState() => _TrackSearchState();
}

class _TrackSearchState extends State<TrackSearch> {
  late final TextEditingController _query = TextEditingController(
    text: widget.initialQuery,
  );
  List<TrackSearchResult>? _hits;
  bool _busy = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() => _busy = true);
    try {
      final hits = await widget.tracker.search(_query.text.trim());
      if (mounted) setState(() => _hits = hits);
    } on Object catch (e) {
      final message = redactUrlQueries('${widget.tracker.name}: $e');
      if (mounted) showError(context, message);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final hits = _hits;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _query,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => unawaited(_search()),
                decoration: const InputDecoration(
                  prefixIcon: Icon(
                    Icons.menu_book_outlined,
                    semanticLabel: 'Search title',
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton(
              style: IconButton.styleFrom(minimumSize: const Size.square(48)),
              icon: const Icon(Icons.search, semanticLabel: 'Search'),
              onPressed: _busy ? null : () => unawaited(_search()),
            ),
          ],
        ),
        if (_busy) const LinearProgressIndicator(),
        if (hits != null && hits.isEmpty)
          const Padding(
            padding: EdgeInsets.all(AppSpacing.sm),
            child: EmptyMark(
              icon: Icons.search_off,
              semanticLabel: 'No matches',
            ),
          ),
        for (final hit in hits ?? const <TrackSearchResult>[])
          ListTile(
            title: Text(hit.title),
            subtitle: hit.chapters == null
                ? null
                : Row(
                    children: [
                      const Icon(
                        Icons.layers_outlined,
                        size: 16,
                        semanticLabel: 'chapters',
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text('${hit.chapters}'),
                    ],
                  ),
            onTap: () => unawaited(widget.onPick(hit)),
          ),
      ],
    );
  }
}
