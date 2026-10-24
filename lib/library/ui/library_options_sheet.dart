import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/library/state/library_controller.dart';
import 'package:kartka/library/state/library_query.dart';

const Map<LibrarySort, String> _sortLabels = {
  LibrarySort.title: 'Title',
  LibrarySort.lastRead: 'Last read',
  LibrarySort.dateAdded: 'Date added',
  LibrarySort.unread: 'Unread count',
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
    final heading = Theme.of(context).textTheme.titleSmall;
    void set(LibraryQuery next) => c.query = next;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Heading('Filter', heading),
            CheckboxListTile(
              title: const Text('Unread'),
              value: q.unreadOnly,
              onChanged: (v) => set(q.copyWith(unreadOnly: v)),
            ),
            CheckboxListTile(
              title: const Text('Downloaded'),
              value: q.downloadedOnly,
              onChanged: (v) => set(q.copyWith(downloadedOnly: v)),
            ),
            CheckboxListTile(
              title: const Text('Tracked'),
              value: q.trackedOnly,
              onChanged: (v) => set(q.copyWith(trackedOnly: v)),
            ),
            _Heading('Sort by', heading),
            RadioGroup<LibrarySort>(
              groupValue: q.sort,
              onChanged: (s) => set(q.copyWith(sort: s)),
              child: Column(
                children: [
                  for (final MapEntry(:key, :value) in _sortLabels.entries)
                    RadioListTile<LibrarySort>(title: Text(value), value: key),
                ],
              ),
            ),
            SwitchListTile(
              title: const Text('Descending'),
              value: !q.ascending,
              onChanged: (v) => set(q.copyWith(ascending: !v)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const new(this.text, this.style);

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.md,
      AppSpacing.sm,
      AppSpacing.md,
      AppSpacing.xs,
    ),
    child: Text(text, style: style),
  );
}
