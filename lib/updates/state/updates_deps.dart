import 'dart:typed_data';

import 'package:kartka/core/repositories/repositories.dart';
import 'package:kartka/library/data/lww.dart';
import 'package:kartka/library/ports.dart';
import 'package:kartka/updates/data/update_feed.dart';

/// Loads cover bytes for a url (network or offline blob).
typedef CoverBytes = Future<Uint8List> Function(String url);

/// Everything the Updates tab reads.
class UpdatesDeps {
  /// Bundles the dependencies.
  const new({
    required this.feed,
    required this.library,
    required this.progress,
    this.updater,
    this.coverLoader,
    this.clock = utcNow,
  });

  /// The local feed of new chapters.
  final UpdateFeed feed;

  /// Library entries (titles, covers; manga removed from it are hidden).
  final LibraryRepository library;

  /// Read state of each chapter.
  final ProgressRepository progress;

  /// "Update all"; `null` hides the refresh action and the pull.
  final LibraryUpdater? updater;

  /// Cover loader; `null` shows placeholders.
  final CoverBytes? coverLoader;

  /// Clock deciding "Today" and "Yesterday".
  final DateTime Function() clock;
}
