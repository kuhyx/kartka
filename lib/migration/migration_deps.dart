import 'package:kartka/core/repositories/repositories.dart';
import 'package:kartka/core/source/manga_source.dart';
import 'package:kartka/platform/blob_store.dart';
import 'package:kartka/tracking/common/chapter_url_resolver.dart';
import 'package:kartka/tracking/common/tracking_service.dart';

/// Everything a migration to Atsumaru reads and writes.
class MigrationDeps {
  /// Creates the set. Without [tracking] no binding moves; without
  /// [chapterNumbers] explicit read marks cannot be mapped (progress still
  /// moves by its own chapter number).
  const new({
    required this.library,
    required this.categories,
    required this.progress,
    required this.findTarget,
    required this.backups,
    this.tracking,
    this.chapterNumbers,
    this.clock = DateTime.now,
  });

  /// Library entries (the accessor's, decorated for sync).
  final LibraryRepository library;

  /// Categories and membership.
  final CategoryRepository categories;

  /// Reading progress and read marks.
  final ProgressRepository progress;

  /// The Atsumaru source, or null when it is not installed.
  final Future<MangaSource?> Function() findTarget;

  /// Where the pre-migration backup goes (the PC-pullable diagnostics
  /// store, so the file can be fetched with adb or from the wrapper).
  final BlobStore backups;

  /// Tracker bindings (`trackers/` sync path).
  final TrackingService? tracking;

  /// Old chapter url → chapter number (browse's chapter cache).
  final ChapterUrlResolver? chapterNumbers;

  /// Clock for the backup name and `updatedAt`.
  final DateTime Function() clock;
}
