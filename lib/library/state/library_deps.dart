import 'dart:typed_data';

import 'package:kartka/library/library_repositories.dart';
import 'package:kartka/library/ports.dart';

/// Loads cover bytes for a url (network or offline blob).
typedef CoverLoader = Future<Uint8List> Function(String url);

/// Everything the Library screen reads, resolved once per screen.
class LibraryDeps {
  /// Bundles the dependencies; ports default to the no-op implementations.
  const new({
    required this.repos,
    this.unread = const NoUnreadCounts(),
    this.downloaded = const NoDownloadedLookup(),
    this.tracked = const NoTrackedLookup(),
    this.clock = utcNow,
    this.coverLoader,
  });

  /// Decorated repositories (always through the accessor, so sync sees UI
  /// writes).
  final LibraryRepositories repos;

  /// Unread counts (browse).
  final UnreadCounts unread;

  /// Offline chapters (downloads).
  final DownloadedLookup downloaded;

  /// Tracker bindings (tracking).
  final TrackedLookup tracked;

  /// Clock for LWW stamps.
  final DateTime Function() clock;

  /// Cover loader; `null` shows placeholders.
  final CoverLoader? coverLoader;
}

/// The current instant in UTC.
DateTime utcNow() => DateTime.now().toUtc();
