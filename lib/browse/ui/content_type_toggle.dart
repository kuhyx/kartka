import 'dart:async';

import 'package:kartka/browse/state/browse_content_type_store.dart';
import 'package:kartka/core/source/content_type.dart';
import 'package:kartka/core/ui/spoken_label.dart';
import 'package:material_ui/material_ui.dart';

/// The checkbox words: kuhy's one allowed word per type (textgate, Q
/// 2026-11-21).
const Map<ContentType, String> _words = {
  ContentType.manga: 'Manga',
  ContentType.manhwa: 'Manhwa',
  ContentType.manhua: 'Manhua',
};

/// The content-type button: a filter icon badged with the number of
/// ticked types; a tap opens a sheet of labelled checkboxes that change the
/// setting at once. When [applied] is false and the setting narrows
/// anything, a [NotAppliedMark] sits before it.
class ContentTypeToggle extends StatelessWidget {
  /// Creates the button over [store].
  const new(this.store, {this.applied = true, super.key});

  /// The synced setting.
  final BrowseContentTypeStore store;

  /// Whether what is on screen honours the setting.
  final bool applied;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ContentTypes>(
    valueListenable: store,
    builder: (context, types, _) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!applied && !types.isAll) const NotAppliedMark(),
        IconButton(
          icon: Badge.count(
            count: types.ticked.length,
            isLabelVisible: !types.isNone,
            child: const Icon(
              Icons.category_outlined,
              semanticLabel: 'Content types',
            ),
          ),
          tooltip: 'Types',
          onPressed: () => showModalBottomSheet<void>(
            context: context,
            builder: (_) => _TypeSheet(store),
          ),
        ),
      ],
    ),
  );
}

class _TypeSheet extends StatelessWidget {
  const new(this.store);

  final BrowseContentTypeStore store;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ValueListenableBuilder<ContentTypes>(
      valueListenable: store,
      builder: (_, types, _) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final t in ContentType.values)
            CheckboxListTile(
              value: types.contains(t),
              title: Text(_words[t]!),
              onChanged: (_) => unawaited(store.toggle(t)),
            ),
        ],
      ),
    ),
  );
}

/// A listing's empty state: a hint icon when no type is ticked (the sheet
/// is the way out), else [orElse].
class TypedEmptyMark extends StatelessWidget {
  /// Creates the mark over [store].
  const new(this.store, {required this.orElse, super.key});

  /// The synced setting.
  final BrowseContentTypeStore store;

  /// The plain "nothing here" mark.
  final Widget orElse;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ContentTypes>(
    valueListenable: store,
    builder: (_, types, _) => types.isNone
        ? const EmptyMark(
            icon: Icons.category_outlined,
            semanticLabel: 'No content type ticked',
          )
        : orElse,
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
