import 'package:collection/collection.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/source/manga_source.dart';
import 'package:kartka/migration/first_value.dart';
import 'package:kartka/migration/migration_deps.dart';
import 'package:kartka/tracking/common/track_binding.dart';

/// Moves library entry [from] to [to] on [target], then drops [from].
///
/// Order, so a failure part-way never loses the old entry: the new entry
/// (keeping `addedAt`), progress and read marks, categories, trackers, and
/// only then the old entry's removal.
///
/// Progress moves BY CHAPTER NUMBER: the target chapter with the old
/// progress number (same page), else the highest target chapter below it
/// (page 0, its own number); never a synthetic url (contracts §13). Explicit
/// read / unread marks move to the target chapters with the same number;
/// a mark whose number is unknown or missing on the target is dropped.
Future<void> migrateEntry(
  MigrationDeps deps, {
  required LibraryEntry from,
  required MangaSource target,
  required MangaSummary to,
}) async {
  final newKey = mangaKeyOf(target.ref.id, to.url);
  final chapters = await target.chapters(to.url);
  await deps.library.upsert(
    LibraryEntry(
      key: newKey,
      sourceId: target.ref.id,
      mangaUrl: to.url,
      title: to.title,
      coverUrl: to.coverUrl ?? from.coverUrl,
      addedAt: from.addedAt,
      updatedAt: deps.clock(),
    ),
  );
  await _moveProgress(deps, from.key, newKey, chapters);
  await _moveMarks(deps, from.key, newKey, chapters);
  await _moveCategories(deps, from.key, newKey);
  await _moveTrackers(deps, from.key, newKey);
  await deps.library.remove(from.key);
}

Future<void> _moveProgress(
  MigrationDeps deps,
  MangaKey from,
  MangaKey to,
  List<ChapterInfo> chapters,
) async {
  final old = await firstValue(deps.progress.watch(from));
  if (old == null) return;
  final number = old.chapterNumber;
  final exact = chapters.firstWhereOrNull((c) => c.number == number);
  ChapterInfo? below;
  for (final c in chapters) {
    final n = c.number;
    if (n != null &&
        n < number &&
        n > (below?.number ?? double.negativeInfinity)) {
      below = c;
    }
  }
  final at = exact ?? below;
  if (at == null) return;
  await deps.progress.record(
    ReadingProgress(
      key: to,
      chapterUrl: at.url,
      chapterNumber: at.number!,
      page: exact == null ? 0 : old.page,
      readAt: old.readAt,
    ),
  );
}

Future<void> _moveMarks(
  MigrationDeps deps,
  MangaKey from,
  MangaKey to,
  List<ChapterInfo> chapters,
) async {
  final numbers = deps.chapterNumbers;
  if (numbers == null) return;
  final read = <String>[];
  final unread = <String>[];
  for (final mark in (await firstValue(
    deps.progress.readMarks(from),
  )).entries) {
    final n = await numbers.numberOf(from, mark.key);
    for (final c in chapters.where((c) => n != null && c.number == n)) {
      (mark.value ? read : unread).add(c.url);
    }
  }
  // An absent mark already counts as unread, so a tombstone (which keeps a
  // chapter below the progress number unread) needs a read mark to flip.
  final marks = [...read, ...unread];
  if (marks.isNotEmpty) await deps.progress.markReadMany(to, marks);
  for (final url in unread) {
    await deps.progress.markUnread(to, url);
  }
}

Future<void> _moveCategories(
  MigrationDeps deps,
  MangaKey from,
  MangaKey to,
) async {
  final cats = (await firstValue(deps.categories.watchMembership()))[from];
  for (final id in cats ?? const <String>{}) {
    await deps.categories.setMembership(to, id, true);
    await deps.categories.setMembership(from, id, false);
  }
}

Future<void> _moveTrackers(
  MigrationDeps deps,
  MangaKey from,
  MangaKey to,
) async {
  final tracking = deps.tracking;
  if (tracking == null) return;
  final bound = [
    for (final b in await tracking.bindings.all())
      if (b.key == from) b,
  ];
  for (final b in bound) {
    // Not `bind()`: that pulls from the tracker over the network.
    await tracking.bindings.put(
      TrackBinding(
        key: to,
        service: b.service,
        remoteId: b.remoteId,
        lastPushedChapter: b.lastPushedChapter,
      ),
    );
    await tracking.unbind(from, b.service);
  }
  if (bound.isNotEmpty) tracking.follow(to);
}
