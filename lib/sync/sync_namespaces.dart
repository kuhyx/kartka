/// The synced namespaces under `/kartka-e2e` and how their nodes merge.
library;

import 'package:kartka/sync/merge/merge_rules.dart';
import 'package:kartka/sync/merge/tracker_merge.dart';
import 'package:kartka/sync/rtdb_transport.dart';

/// Merge rule and key depth of each synced namespace.
const Map<String, (int, Merge)> kSyncNamespaces = {
  'library': (1, mergeLwwNode),
  'categories': (1, mergeLwwNode),
  'membership': (2, mergeRegister),
  'progress': (1, mergeProgress),
  'read': (2, mergeRegister),
  'trackers': (2, mergeTracker),
  // `{key, value|enc, hlc}`: whole-node LWW per setting (§16).
  'settings': (1, mergeRegister),
};

/// One node that changed because of a remote merge.
typedef RemoteChange = ({String path, Node node});

/// Opens a transport, or returns null while this device is signed out.
typedef TransportOpener = Future<RtdbTransport?> Function();

/// Flattens a namespace subtree into `{<ns>/<k1>[/<k2>]: node}`.
Map<String, Node> flattenNodes(String ns, Object? tree, int depth) {
  final out = <String, Node>{};
  void walk(String prefix, Object? raw, int level) {
    final node = fromRtdb(raw);
    if (node is! Map<String, Object?>) return;
    if (level == depth) {
      out[prefix] = node;
      return;
    }
    for (final e in node.entries) {
      walk('$prefix/${e.key}', e.value, level + 1);
    }
  }

  walk(ns, tree, 0);
  return out;
}

/// The newer of [last] and every Hlc in [node], so local ticks stay ahead
/// of everything observed from peers.
String? newestClock(Node node, String? last) {
  final clocks = switch (node[kHlcField]) {
    final String c => [c],
    final Map<Object?, Object?> m => m.values.whereType<String>(),
    _ => const <String>[],
  };
  var newest = last;
  for (final c in clocks) {
    if (compareHlc(c, newest) > 0) newest = c;
  }
  return newest;
}

/// Undoes RTDB's array coercion: an object whose keys are all small
/// integers (a numeric remoteId, a category named "1") reads back as a List.
/// Turned back into a map, recursively, so it compares equal to what was
/// written instead of looking "behind" and being re-pushed every poll.
Object? fromRtdb(Object? value) => switch (value) {
  final List<Object?> l => <String, Object?>{
    for (var i = 0; i < l.length; i++)
      if (l[i] != null) '$i': fromRtdb(l[i]),
  },
  final Map<String, Object?> m => {
    for (final e in m.entries) e.key: fromRtdb(e.value),
  },
  _ => value,
};
