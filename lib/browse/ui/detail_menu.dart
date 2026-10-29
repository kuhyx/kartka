import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:kartka/app/routes.dart';
import 'package:kartka/browse/browse_scope.dart';
import 'package:kartka/browse/state/chapter_order.dart';
import 'package:kartka/browse/state/manga_detail_controller.dart';
import 'package:kartka/core/models/models.dart';

/// The detail screen's app-bar overflow ("More"): Read, library
/// membership, downloads, the "Unread first" sort and every registered
/// `MangaDetailSlot` (e.g. Track, Migrate). Continue is the FAB.
class DetailMenu extends StatefulWidget {
  /// Creates the menu; [read] is the current read set.
  const new({
    required this.controller,
    required this.details,
    required this.read,
    super.key,
  });

  /// Detail state.
  final MangaDetailController controller;

  /// Loaded details (slots need them).
  final MangaDetails details;

  /// Read chapter urls.
  final Set<String> read;

  @override
  State<DetailMenu> createState() => _DetailMenuState();
}

class _DetailMenuState extends State<DetailMenu> {
  final _menu = MenuController();

  // Held here, not in a StreamBuilder inside the menu: the menu builds its
  // children anew on every open, and the library stream may be
  // single-subscription.
  late final StreamSubscription<bool> _library;
  bool _inLibrary = false;

  @override
  void initState() {
    super.initState();
    _library = widget.controller.inLibrary().listen(
      (inLibrary) => setState(() => _inLibrary = inLibrary),
    );
  }

  @override
  void dispose() {
    unawaited(_library.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final deps = BrowseScope.of(context);
    final first = firstUnread(c.chapters, widget.read);
    return MenuAnchor(
      controller: _menu,
      menuChildren: [
        if (first != null)
          MenuItemButton(
            key: const ValueKey('read'),
            leadingIcon: const Icon(Icons.menu_book_outlined),
            onPressed: () => unawaited(
              context.push(readRoute(c.sourceId, c.mangaUrl, first.url)),
            ),
            child: const Text('Read'),
          ),
        MenuItemButton(
          key: const ValueKey('library'),
          leadingIcon: Icon(
            _inLibrary ? Icons.favorite : Icons.favorite_border,
          ),
          onPressed: () => unawaited(c.setInLibrary(add: !_inLibrary)),
          child: Text(_inLibrary ? 'In library' : 'Add to library'),
        ),
        if (deps.downloads != null) ...[
          MenuItemButton(
            leadingIcon: const Icon(Icons.download_outlined),
            onPressed: () => unawaited(c.download(c.chapters)),
            child: const Text('Download all'),
          ),
          MenuItemButton(
            leadingIcon: const Icon(Icons.download_outlined),
            onPressed: () =>
                unawaited(c.download(unreadOf(c.chapters, widget.read))),
            child: const Text('Download unread'),
          ),
        ],
        CheckboxMenuButton(
          key: const ValueKey('unread-first'),
          value: deps.chapterSort.value,
          onChanged: (on) =>
              unawaited(deps.chapterSort.set(unreadFirst: on ?? false)),
          child: const Text('Unread first'),
        ),
        // A slot is an arbitrary widget, not a menu item: close the menu
        // once it is tapped, as a menu item would.
        for (final slot in deps.detailSlots)
          Listener(
            onPointerUp: (_) => _menu.close(),
            child: slot.build(context, c.key, widget.details),
          ),
      ],
      builder: (context, menu, _) => IconButton(
        tooltip: 'More',
        icon: const Icon(Icons.more_vert),
        onPressed: () => menu.isOpen ? menu.close() : menu.open(),
      ),
    );
  }
}
