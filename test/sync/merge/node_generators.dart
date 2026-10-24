import 'package:crdt_sync/crdt_sync.dart' show Hlc;
import 'package:glados/glados.dart';
import 'package:kartka/sync/merge/merge_rules.dart';
import 'package:kartka/sync/merge/tracker_merge.dart';

/// Small domains on purpose: collisions (equal clocks, equal positions) are
/// where merge rules break, so the generators make them common.
extension SyncNodeAnys on Any {
  /// A crdt_sync Hlc string from a tiny clock space, or null (unclocked).
  Generator<String?> get hlcStr => combine3(
    intInRange(0, 4),
    intInRange(0, 3),
    choose(['dev-a', 'dev-b', 'dev-c']),
    (wall, counter, node) =>
        Hlc(wallTimeMs: wall * 1000, counter: counter, nodeId: node).toStr(),
  ).nullable;

  /// A scalar JSON value as RTDB stores it.
  Generator<Object?> get scalar => oneOfGen([
    choose<Object?>(['x', 'y', 'One Piece']),
    choose<Object?>([true, false]),
    choose<Object?>([0, 1, 2.5]),
    always<Object?>(null),
  ]);

  /// One field of a per-field LWW node: (name, present?, value, clock).
  Generator<(String, bool, Object?, String?)> get lwwField => combine4(
    choose(['title', 'coverUrl', 'removed', 'name']),
    this.bool,
    scalar,
    hlcStr,
    (f, present, v, c) => (f, present, v, c),
  );

  /// A `library/` or `categories/` node: flat fields plus an `hlc` map.
  Generator<Node> get lwwNode => list(lwwField).map((fields) {
    final node = <String, Object?>{};
    final clocks = <String, Object?>{};
    for (final (name, present, value, clock) in fields) {
      if (present) node[name] = value;
      if (clock != null) clocks[name] = clock;
    }
    if (clocks.isNotEmpty) node['hlc'] = clocks;
    return node;
  });

  /// A `membership/` or `read/` node: `{member|read, hlc, key|url}`.
  Generator<Node> get registerNode => combine3(
    this.bool,
    hlcStr,
    choose(['k1', 'k2']),
    (flag, clock, key) => <String, Object?>{
      'read': flag,
      'hlc': ?clock,
      'url': key,
    },
  );

  /// A `progress/` node, the ReadingProgress JSON shape.
  Generator<Node> get progressNode => combine4(
    choose<double?>([null, 1, 2, 2.5]),
    intInRange(0, 3),
    choose(['2026-10-24T10:00:00.000Z', '2026-10-24T11:00:00.000Z']),
    choose(['/c/1', '/c/2']),
    (number, page, readAt, url) => <String, Object?>{
      'key': 'mangadex|/manga/1',
      'chapterUrl': url,
      'chapterNumber': ?number,
      'page': page,
      'readAt': readAt,
    },
  );

  /// A `trackers/` node: an LWW binding plus a per-remoteId max map.
  Generator<Node> get trackerNode => combine4(
    choose<String?>(['21', '42', null]),
    hlcStr,
    map(choose(['21', '42']), intInRange(0, 5)),
    this.bool,
    (id, clock, pushed, removed) =>
        trackerNode2(id, clock, pushed, removed: removed),
  );

  static Node trackerNode2(
    String? id,
    String? clock,
    Map<String, int> pushed, {
    required bool removed,
  }) => normalTracker({
    'key': 'k',
    'service': 'anilist',
    'remoteId': ?id,
    'removed': removed,
    kHlcField: ?clock,
    if (pushed.isNotEmpty) kPushedField: pushed,
  });

  /// Picks one of [gens] (glados has no built-in union).
  Generator<T> oneOfGen<T>(List<Generator<T>> gens) =>
      intInRange(0, gens.length).bind((i) => gens[i]);
}
