/// Merge rule for `trackers/<mangaKeyHash>/<service>` (contracts §4: max).
///
/// A node is `{key, service, remoteId, removed, hlc, pushed, ...}`: the
/// binding itself (`remoteId` / `removed`) is a last-writer-wins register on
/// `hlc`, and `pushed: {<remoteId>: chapters}` is a grow-only max map. The
/// readable `lastPushedChapter` is derived, `pushed[remoteId]`, so it never
/// decreases for a binding. Keeping the max per remoteId (rather than one
/// number) is what makes this a true join: a rebind and back never loses a
/// chapter count through an intermediate merge.
library;

import 'dart:math';

import 'package:kartka/sync/merge/merge_rules.dart';
import 'package:kartka/sync/rtdb_transport.dart';

/// Per-remoteId max map key inside a tracker node.
const String kPushedField = 'pushed';

/// Joins two tracker nodes.
Node mergeTracker(Node a, Node b) {
  final register = mergeRegister(_register(a), _register(b));
  final pushed = <String, Object?>{..._pushed(a)};
  for (final MapEntry(:key, :value) in _pushed(b).entries) {
    final mine = pushed[key];
    pushed[key] = mine is int ? max(mine, value) : value;
  }
  return normalTracker({...register, kPushedField: pushed});
}

/// Recomputes the derived `lastPushedChapter` and drops empty fields.
Node normalTracker(Node node) {
  final pushed = node[kPushedField];
  final id = node['remoteId'];
  final last = pushed is Map && id is String ? pushed[rtdbKey(id)] : null;
  return rtdbNormal({
    ...node,
    if (pushed is Map && pushed.isEmpty) kPushedField: null,
    'lastPushedChapter': last,
  });
}

Node _register(Node n) => {
  for (final f in const ['key', 'service', 'remoteId', 'removed', kHlcField])
    if (n.containsKey(f)) f: n[f],
};

Map<String, int> _pushed(Node n) => {
  if (n[kPushedField] case final Map<Object?, Object?> m)
    for (final MapEntry(:key, :value) in m.entries)
      if (value is num) '$key': value.toInt(),
};
