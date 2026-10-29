import 'dart:async';

import 'package:kartka/browse/browse_scope.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/repositories/library_repository.dart';

/// What the detail screen can show for [key] without the network: the
/// last fetched details (`BrowseDeps.details`; else the library entry's
/// title and cover) plus the stored chapter list (source order, empty when
/// none was stored). Null when the manga is not in the library.
Future<(MangaDetails, List<ChapterInfo>)?> storedDetail(
  BrowseDeps deps,
  MangaKey key,
) async {
  final entry = await libraryEntry(deps.library, key);
  if (entry == null) return null;
  final (details, chapters) = await (
    deps.details.read(key),
    deps.chapters.stored(key),
  ).wait;
  return (
    details ??
        MangaDetails(
          sourceId: entry.sourceId,
          url: entry.mangaUrl,
          title: entry.title,
          coverUrl: entry.coverUrl,
        ),
    chapters ?? const <ChapterInfo>[],
  );
}

/// [key]'s entry in the library's first emission, or null (also on a read
/// error). Like `watch().first`, but it completes without awaiting the
/// subscription's cancel, which can finish outside the caller's zone.
Future<LibraryEntry?> libraryEntry(LibraryRepository library, MangaKey key) {
  final found = Completer<LibraryEntry?>();
  late final StreamSubscription<List<LibraryEntry>> sub;
  sub = library.watch().listen(
    (entries) {
      found.complete(entries.where((e) => e.key == key).firstOrNull);
      unawaited(sub.cancel());
    },
    onError: (Object _) {
      found.complete(null);
      unawaited(sub.cancel());
    },
  );
  return found.future;
}
