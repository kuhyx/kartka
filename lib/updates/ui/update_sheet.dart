import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kartka/app/routes.dart';
import 'package:kartka/updates/state/update_rows.dart';
import 'package:kartka/updates/state/updates_deps.dart';
import 'package:kartka/updates/ui/update_groups.dart';
import 'package:kartka/updates/ui/update_row_tiles.dart';

/// Opens the bottom sheet of [group]: its manga heading, an "Open manga"
/// action and its new chapters by day. A tap closes the sheet, then goes to
/// the reader or the detail page.
Future<void> showUpdateSheet(
  BuildContext context,
  UpdateGroup group,
  CoverBytes? covers,
) {
  final router = GoRouter.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheet) {
      void open(String route) {
        Navigator.of(sheet).pop();
        unawaited(router.push<void>(route));
      }

      final entry = group.entry;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          updateRowTile(sheet, MangaRow(entry), covers, open: open),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: IconButton(
                onPressed: () =>
                    open(mangaRoute(entry.sourceId, entry.mangaUrl)),
                icon: const Icon(
                  Icons.open_in_new,
                  semanticLabel: 'Open manga',
                ),
              ),
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              children: [
                for (final row in group.rows)
                  updateRowTile(sheet, row, covers, open: open),
              ],
            ),
          ),
        ],
      );
    },
  );
}
