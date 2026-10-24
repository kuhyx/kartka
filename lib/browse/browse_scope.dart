import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:kartka/browse/manga_detail_slot.dart';
import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/browse/source_registry.dart';
import 'package:kartka/browse/state/chapter_store.dart';
import 'package:kartka/core/repositories/repositories.dart';
import 'package:kartka/downloads/download_service.dart';

/// Loads cover image bytes for a cover url (web needs the wrapper proxy, so
/// covers never go through `Image.network`).
typedef CoverLoader = Future<Uint8List> Function(String url);

/// Everything the browse screens need, resolved once from the registry.
class BrowseDeps {
  /// Creates the dependency set. Optional ports degrade gracefully: no
  /// [health] → name order and no badges; no [downloads] → no download
  /// buttons; no [downloadService] → no cancel / delete buttons; no
  /// [coverLoader] → placeholder covers.
  new({
    required this.sources,
    required this.chapters,
    required this.library,
    required this.progress,
    this.downloads,
    this.downloadService,
    this.health,
    this.detailSlots = const [],
    this.coverLoader,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  /// Live source list.
  final SourceRegistry sources;

  /// Chapter cache shared with the unread-count and resolver ports.
  final ChapterStore chapters;

  /// Library membership.
  final LibraryRepository library;

  /// Read marks and reading progress.
  final ProgressRepository progress;

  /// Offline downloads, when the downloads part is registered.
  final DownloadRepository? downloads;

  /// Cancel and delete per chapter (DOCS-contracts-runtime §15), when the
  /// downloads part is registered; usually the same object as [downloads].
  final DownloadService? downloadService;

  /// Source-health ranking, when the source_health part is registered.
  final SourceHealthLookup? health;

  /// Extra detail-screen actions (e.g. the tracking button).
  final List<MangaDetailSlot> detailSlots;

  /// Cover bytes loader.
  final CoverLoader? coverLoader;

  /// Clock for `addedAt` / `updatedAt` (injected in tests).
  final DateTime Function() clock;
}

/// Provides [BrowseDeps] to the browse screens.
class BrowseScope extends InheritedWidget {
  /// Creates the scope.
  const new({required this.deps, required super.child, super.key});

  /// The provided dependencies.
  final BrowseDeps deps;

  /// The nearest [BrowseDeps]; throws when no [BrowseScope] is above.
  static BrowseDeps of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<BrowseScope>();
    if (scope == null) throw StateError('No BrowseScope above $context');
    return scope.deps;
  }

  @override
  bool updateShouldNotify(BrowseScope oldWidget) => deps != oldWidget.deps;
}
