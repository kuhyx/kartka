import 'package:kartka/core/models/models.dart';
import 'package:kartka/migration/dedupe/dupe_facts.dart';
import 'package:kartka/migration/migration_deps.dart';
import 'package:kartka/migration/migrator.dart';
import 'package:kartka/tracking/common/track_binding.dart';

/// Merges library entry [loser] onto [winner], then drops [loser].
///
/// The winner is written first and the loser removed last, so a failure
/// part-way never loses an entry. The winner keeps the earlier `addedAt`
/// and gets a fresh `updatedAt` (so two devices picking opposite winners
/// leave one live entry under LWW, not two tombstones). Every chapter
/// number read on the loser is marked read on the winner (explicit unread
/// marks never move: the read sets are unioned), the further progress
/// wins, categories are unioned, and a tracker binding moves only for a
/// service the winner is not bound to. Downloads stay where they are.
Future<void> mergeInto(
  MigrationDeps deps, {
  required Dupe winner,
  required Dupe loser,
}) async {
  final w = winner.entry;
  final l = loser.entry;
  await deps.library.upsert(
    LibraryEntry(
      key: w.key,
      sourceId: w.sourceId,
      mangaUrl: w.mangaUrl,
      title: w.title,
      coverUrl: w.coverUrl,
      addedAt: l.addedAt.isBefore(w.addedAt) ? l.addedAt : w.addedAt,
      updatedAt: deps.clock().toUtc(),
    ),
  );
  await _unionRead(deps, winner, loser);
  await moveProgress(deps, l.key, w.key, winner.facts.chapters);
  await moveCategories(deps, l.key, w.key);
  await _mergeTrackers(deps, l.key, w.key);
  await deps.library.remove(l.key);
}

Future<void> _unionRead(MigrationDeps deps, Dupe winner, Dupe loser) async {
  final read = {
    for (final c in loser.facts.chapters)
      if (loser.facts.readUrls.contains(c.url)) ?c.number,
  };
  final urls = [
    for (final c in winner.facts.chapters)
      if (read.contains(c.number) && !winner.facts.readUrls.contains(c.url))
        c.url,
  ];
  if (urls.isNotEmpty) await deps.progress.markReadMany(winner.entry.key, urls);
}

Future<void> _mergeTrackers(
  MigrationDeps deps,
  MangaKey from,
  MangaKey to,
) async {
  final tracking = deps.tracking;
  if (tracking == null) return;
  final all = await tracking.bindings.all();
  final bound = {
    for (final b in all)
      if (b.key == to) b.service,
  };
  var moved = false;
  for (final b in all.where((b) => b.key == from)) {
    if (!bound.contains(b.service)) {
      // Not `bind()`: that pulls from the tracker over the network.
      await tracking.bindings.put(
        TrackBinding(
          key: to,
          service: b.service,
          remoteId: b.remoteId,
          lastPushedChapter: b.lastPushedChapter,
        ),
      );
      moved = true;
    }
    await tracking.unbind(from, b.service);
  }
  if (moved) tracking.follow(to);
}
