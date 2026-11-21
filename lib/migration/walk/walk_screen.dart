import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:kartka/app/cached_cover.dart';
import 'package:kartka/core/ui/spoken_label.dart';
import 'package:kartka/migration/migration_outcome.dart';
import 'package:kartka/migration/walk/candidate_card.dart';
import 'package:kartka/migration/walk/walk_auto.dart';
import 'package:kartka/migration/walk/walk_controller.dart';
import 'package:kartka/migration/walk/walk_parts.dart';
import 'package:material_ui/material_ui.dart';

/// The one-by-one migration: the current library entry on top, its
/// alternatives below as cards (best first). A tap on a card migrates the
/// entry there and shows the next one; skip, back and a manual search are
/// icon buttons; the auto-fix button migrates every strong match in a row
/// ([WalkAutoPass]) with a count and a stop button. Word-free: covers,
/// titles, source names, numbers, dates.
class MigrationWalkScreen extends StatefulWidget {
  /// Creates the screen; it loads and disposes [controller].
  const new({required this.controller, this.coverLoader, super.key});

  /// Drives the walk.
  final MigrationWalkController controller;

  /// Cover bytes (the library's cover cache).
  final CoverBytes? coverLoader;

  @override
  State<MigrationWalkScreen> createState() => _MigrationWalkScreenState();
}

class _MigrationWalkScreenState extends State<MigrationWalkScreen> {
  var _manual = false;

  MigrationWalkController get _c => widget.controller;

  late final _auto = WalkAutoPass(_c);

  @override
  void initState() {
    super.initState();
    unawaited(_c.load());
  }

  @override
  void dispose() {
    _auto.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_c, _auto]),
    builder: (context, _) {
      final walking = _c.current != null;
      return Scaffold(
        appBar: AppBar(
          title: walking
              ? Text('${_c.index + 1} / ${_c.items.length}')
              : const Icon(Icons.swap_horiz, semanticLabel: 'Migrate'),
          actions: [
            if (_c.index > 0)
              _action(Icons.skip_previous, 'Previous entry', _c.back),
            if (_auto.running) ...[
              const Icon(Icons.auto_fix_high, semanticLabel: 'Migrated'),
              Text('${_auto.moved}'),
              IconButton(
                style: IconButton.styleFrom(minimumSize: const Size.square(48)),
                onPressed: _auto.stop,
                icon: const Icon(Icons.stop, semanticLabel: 'Stop'),
              ),
            ] else if (_c.current?.pending != null)
              _action(
                Icons.auto_fix_high,
                'Migrate every strong match',
                () => unawaited(_auto.run()),
              ),
            if (walking) ...[
              _action(
                Icons.search,
                'Search by hand',
                () => setState(() => _manual = !_manual),
              ),
              _action(Icons.skip_next, 'Skip', _c.skip),
            ],
          ],
        ),
        body: _body(context),
      );
    },
  );

  Widget _action(IconData icon, String label, VoidCallback onPressed) =>
      IconButton(
        style: IconButton.styleFrom(minimumSize: const Size.square(48)),
        onPressed: _c.busy || _auto.running ? null : onPressed,
        icon: Icon(icon, semanticLabel: label),
      );

  Widget _body(BuildContext context) {
    if (!_c.loaded) return const LinearProgressIndicator();
    final item = _c.current;
    if (item == null) {
      return _c.items.isEmpty
          ? const EmptyMark(
              icon: Icons.done_all,
              semanticLabel: 'Nothing to migrate.',
            )
          : Column(
              children: [
                Expanded(
                  child: EmptyMark(
                    icon: Icons.done_all,
                    semanticLabel:
                        'Done. Migrated ${_c.migrated}, failed ${_c.failed}',
                  ),
                ),
                if (_c.backupKey != null) _outcome(),
              ],
            );
    }
    final found = item.found;
    final loader = widget.coverLoader;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        if (_c.busy) const LinearProgressIndicator(),
        if (_c.backupError != null) _outcome(),
        WalkHeader(item: item, loader: loader),
        if (item.error case final e?) errorMark(e),
        if (item.migratedTo case final to?)
          CandidateCard(candidate: to, loader: loader),
        if (_manual)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: TextField(
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search, semanticLabel: 'Search'),
              ),
              onSubmitted: _c.search,
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        if (found == null)
          const SpokenLabel(
            semanticLabel: 'Searching…',
            child: LinearProgressIndicator(),
          )
        else ...[
          LaneStrip(found.lanes),
          const SizedBox(height: AppSpacing.sm),
          if (found.best.isEmpty)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Icon(
                Icons.search_off,
                size: 48,
                semanticLabel: 'No alternative found',
              ),
            ),
          if (item.migratedTo == null)
            for (final c in found.best)
              CandidateCard(
                candidate: c,
                loader: loader,
                onTap: _c.busy || _auto.running
                    ? null
                    : () => unawaited(_c.migrateTo(c)),
              ),
        ],
      ],
    );
  }

  Widget _outcome() => Padding(
    padding: const EdgeInsets.all(AppSpacing.md),
    child: MigrationOutcome(
      migrated: _c.migrated,
      failed: _c.failed,
      backupKey: _c.backupKey,
      error: _c.backupError,
    ),
  );
}
