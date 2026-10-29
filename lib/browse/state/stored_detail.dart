import 'dart:async';

import 'package:kartka/browse/browse_scope.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/repositories/library_repository.dart';

/// What the detail screen can show for [key] without the network: details
/// from its library entry plus the stored chapter list (source order, empty
/// when none was stored). Null when the manga is not in the library.
Future<(MangaDetails, List<ChapterInfo>)?> storedDetail(
  BrowseDeps deps,
  MangaKey key,
) async {
  final entry = await _entry(deps.library, key);
  if (entry == null) return null;
  final chapters = await deps.chapters.stored(key);
  return (
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
Future<LibraryEntry?> _entry(LibraryRepository library, MangaKey key) {
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
