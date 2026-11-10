import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/core/ui/section_mark.dart';
import 'package:kartka/library/state/library_controller.dart';
import 'package:kartka/library/state/library_query.dart';

/// Each sort's glyph and its spoken name.
const Map<LibrarySort, (IconData, String)> _sorts = {
  LibrarySort.title: (Icons.sort_by_alpha, 'Title'),
  LibrarySort.lastRead: (Icons.history, 'Last read'),
  LibrarySort.dateAdded: (Icons.event_outlined, 'Date added'),
  LibrarySort.unread: (Icons.numbers, 'Unread count'),
};

/// Opens the sort and filter sheet; changes apply live.
Future<void> showLibraryOptions(BuildContext context, LibraryController c) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          ListenableBuilder(listenable: c, builder: (context, _) => _Sheet(c)),
    );

class _Sheet extends StatelessWidget {
  const new(this.c);

  final LibraryController c;

  @override
  Widget build(BuildContext context) {
    final q = c.query;
    void set(LibraryQuery next) => c.query = next;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionMark(Icons.filter_list, semanticLabel: 'Filter'),
            CheckboxListTile(
              secondary: const Icon(
                Icons.mark_chat_unread_outlined,
                semanticLabel: 'Unread',
              ),
              value: q.unreadOnly,
              onChanged: (v) => set(q.copyWith(unreadOnly: v)),
            ),
            CheckboxListTile(
              secondary: const Icon(
                Icons.download_done,
                semanticLabel: 'Downloaded',
              ),
              value: q.downloadedOnly,
              onChanged: (v) => set(q.copyWith(downloadedOnly: v)),
            ),
            CheckboxListTile(
              secondary: const Icon(Icons.sync_alt, semanticLabel: 'Tracked'),
              value: q.trackedOnly,
              onChanged: (v) => set(q.copyWith(trackedOnly: v)),
            ),
            const SectionMark(Icons.sort, semanticLabel: 'Sort by'),
            RadioGroup<LibrarySort>(
              groupValue: q.sort,
              onChanged: (s) => set(q.copyWith(sort: s)),
              child: Column(
                children: [
                  for (final MapEntry(:key, value: (icon, name))
                      in _sorts.entries)
                    RadioListTile<LibrarySort>(
                      secondary: Icon(icon, semanticLabel: name),
                      value: key,
                    ),
                ],
              ),
            ),
            SwitchListTile(
              secondary: const Icon(
                Icons.arrow_downward,
                semanticLabel: 'Descending',
              ),
              value: !q.ascending,
              onChanged: (v) => set(q.copyWith(ascending: !v)),
            ),
          ],
        ),
      ),
    );
  }
}
