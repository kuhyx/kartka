import 'dart:async';

import 'package:kartka/browse/state/browse_content_type_store.dart';
import 'package:kartka/core/source/content_type.dart';
import 'package:material_ui/material_ui.dart';

const Map<ContentType, IconData> _icons = {
  ContentType.manga: Icons.looks_one_outlined,
  ContentType.mangaManhwa: Icons.looks_two_outlined,
  ContentType.all: Icons.all_inclusive,
};

const Map<ContentType, String> _labels = {
  ContentType.manga: 'Manga only',
  ContentType.mangaManhwa: 'Manga and manhwa',
  ContentType.all: 'All types',
};

/// The content-type toggle (textgate: icons only): one type, two types,
/// everything; a tap moves to the next. When [applied] is false and the
/// setting narrows anything, a [NotAppliedMark] sits before it.
class ContentTypeToggle extends StatelessWidget {
  /// Creates the toggle over [store].
  const new(this.store, {this.applied = true, super.key});

  /// The synced setting.
  final BrowseContentTypeStore store;

  /// Whether what is on screen honours the setting.
  final bool applied;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ContentType>(
    valueListenable: store,
    builder: (context, type, _) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!applied && type != ContentType.all) const NotAppliedMark(),
        IconButton(
          icon: Icon(_icons[type], semanticLabel: _labels[type]),
          onPressed: () => unawaited(store.cycle()),
        ),
      ],
    ),
  );
}

/// "This source lists everything": it has no usable type filter.
class NotAppliedMark extends StatelessWidget {
  /// Creates the mark.
  const new({super.key});

  @override
  Widget build(BuildContext context) => Icon(
    Icons.filter_alt_off_outlined,
    color: Theme.of(context).colorScheme.onSurfaceVariant,
    semanticLabel: 'Type filter not applied here',
  );
}
