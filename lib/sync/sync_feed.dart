/// The change feed beside `revs/` (contracts §12, refined 2026-10-24).
///
/// Every push also writes `log/<deviceId>/r<rev>`: the pushed node paths
/// joined by `\n`, or `*` when more than [kFeedMaxListed] paths changed. The
/// same atomic update prunes `r<rev - kFeedWindow>`. A peer whose last seen
/// revision is at most [kFeedWindow] behind reads that tiny log and GETs only
/// the listed paths; anything else falls back to a full pull. That is what
/// keeps a page turn from costing a download of the whole `read/` subtree.
library;

import 'package:kartka/sync/rtdb_transport.dart';
import 'package:kartka/sync/sync_shadow.dart';

/// Revisions kept per device in `log/`.
const int kFeedWindow = 50;

/// A push listing more paths than this logs `*` (pull everything) instead.
const int kFeedMaxListed = 500;

/// A delta needing more GETs than this is fetched as a full pull instead.
const int kFeedMaxDelta = 200;

/// Paths per PATCH when pushing a large backlog.
const int kPushChunk = 1000;

/// The log entry value for a push of [paths].
String feedEntry(List<String> paths) =>
    paths.length > kFeedMaxListed ? '*' : paths.join('\n');

/// The revs + log updates that publish revision [rev] of [paths].
Map<String, Object?> feedUpdates(
  String deviceId,
  int rev,
  List<String> paths,
) => {
  'revs/$deviceId': '$rev',
  'log/$deviceId/r$rev': feedEntry(paths),
  if (rev > kFeedWindow) 'log/$deviceId/r${rev - kFeedWindow}': null,
};

/// What a poll must fetch: everything, or just `paths`.
typedef PullPlan = ({bool full, Set<String> paths});

const PullPlan _full = (full: true, paths: {});

/// Plans the pull from peers' current revisions [now] vs the [seen] ones.
Future<PullPlan> planPull(
  RtdbTransport transport,
  Map<String, String> now,
  Map<String, String> seen,
) async {
  final paths = <String>{};
  for (final MapEntry(key: device, value: rev) in now.entries) {
    if (seen[device] == rev) continue;
    final from = int.tryParse(seen[device] ?? '');
    final to = int.tryParse(rev);
    if (from == null || to == null || to < from || to - from > kFeedWindow) {
      return _full;
    }
    final log = await transport.get('log/$device');
    if (log is! Map) return _full;
    for (var r = from + 1; r <= to; r++) {
      final entry = log['r$r'];
      if (entry is! String || entry == '*') return _full;
      paths.addAll(entry.split('\n').where((p) => p.isNotEmpty));
    }
    if (paths.length > kFeedMaxDelta) return _full;
  }
  return (full: false, paths: paths);
}

/// Pushes every dirty node of [shadow] in chunks of [kPushChunk], with the
/// revision and feed entry in the last chunk; false when nothing was dirty.
Future<bool> pushDirty(
  RtdbTransport transport,
  SyncShadow shadow,
  String deviceId,
) async {
  final pending = shadow.dirty.toList()..sort();
  if (pending.isEmpty) return false;
  for (var i = 0; i < pending.length; i += kPushChunk) {
    final end = (i + kPushChunk).clamp(0, pending.length);
    await transport.patch({
      for (final path in pending.sublist(i, end)) path: shadow.node(path),
      if (end == pending.length)
        ...feedUpdates(deviceId, await shadow.nextRev(), pending),
    });
  }
  await shadow.clearDirty(pending);
  return true;
}
