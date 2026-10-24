/// The merge rules for every synced RTDB node (DOCS-contracts §4, §12, §13).
///
/// Each rule is a *join*: commutative, associative and idempotent, so devices
/// converge no matter in which order, or how often, they merge each other's
/// nodes. Every rule is "max over a total order", which is what makes that
/// hold even for malformed or colliding input: ties that the clocks cannot
/// break fall back to a canonical comparison of the JSON itself.
library;

import 'dart:convert';

import 'package:crdt_sync/crdt_sync.dart' show Hlc;

/// One decoded RTDB node.
typedef Node = Map<String, Object?>;

/// A two-way merge of nodes stored at the same path.
typedef Merge = Node Function(Node a, Node b);

/// The per-field clock map key inside an LWW node.
const String kHlcField = 'hlc';

/// Orders two Hlc strings; null and unparsable clocks sort lowest.
int compareHlc(String? a, String? b) {
  final ha = _parseHlc(a);
  final hb = _parseHlc(b);
  if (ha == null || hb == null) {
    return (ha == null ? 0 : 1) - (hb == null ? 0 : 1);
  }
  return ha.compareTo(hb);
}

Hlc? _parseHlc(String? text) {
  if (text == null) return null;
  try {
    return Hlc.fromStr(text);
  } on FormatException {
    return null;
  }
}

/// Deterministic JSON text with map keys sorted, so equal values always
/// encode equally. The tie-breaker of last resort and the equality tests use.
String canon(Object? value) => jsonEncode(_sorted(value));

Object? _sorted(Object? value) => switch (value) {
  final Map<Object?, Object?> m => {
    for (final k in (m.keys.map((k) => '$k').toList()..sort()))
      k: _sorted(m[k]),
  },
  final List<Object?> l => l.map(_sorted).toList(),
  // RTDB hands 2.0 back as 2; without this a pushed node would never compare
  // equal to its own echo and would be re-pushed forever.
  final double d when d.isFinite && d == d.truncateToDouble() => d.toInt(),
  _ => value,
};

/// Drops null fields and an empty clock map, which RTDB would drop anyway,
/// so a node compares equal to what reading it back returns.
Node rtdbNormal(Node node) {
  final out = <String, Object?>{
    for (final e in node.entries)
      if (e.value != null) e.key: e.value,
  };
  if (out[kHlcField] case final Map<Object?, Object?> m when m.isEmpty) {
    out.remove(kHlcField);
  }
  return out;
}

/// Per-field last-writer-wins for `library/` and `categories/` nodes.
///
/// Every flat field is resolved on its own: the side whose `hlc[field]` is
/// greater wins the value *and* the clock together. Without a clock, a
/// present field beats an absent one, then the canonical value decides.
Node mergeLwwNode(Node a, Node b) {
  final ca = _clocks(a);
  final cb = _clocks(b);
  final out = <String, Object?>{};
  final clocks = <String, Object?>{};
  final fields = {...a.keys, ...b.keys}..remove(kHlcField);
  for (final field in fields) {
    final aWins = _fieldOrder(a, ca[field], b, cb[field], field) >= 0;
    final (src, clock) = aWins ? (a, ca[field]) : (b, cb[field]);
    if (src.containsKey(field)) out[field] = src[field];
    if (clock != null) clocks[field] = clock;
  }
  // A clock can exist for a field that is absent on both sides (a written
  // null that RTDB dropped); keep the newest one so it still wins later.
  for (final field in {...ca.keys, ...cb.keys}.difference(fields)) {
    final clock = compareHlc(ca[field], cb[field]) >= 0 ? ca[field] : cb[field];
    if (clock != null) clocks[field] = clock;
  }
  if (clocks.isNotEmpty) out[kHlcField] = clocks;
  return out;
}

Map<String, String?> _clocks(Node node) {
  final raw = node[kHlcField];
  if (raw is! Map) return const {};
  return {
    for (final e in raw.entries)
      '${e.key}': e.value is String ? e.value as String : null,
  };
}

int _fieldOrder(Node a, String? ca, Node b, String? cb, String field) {
  final byClock = compareHlc(ca, cb);
  if (byClock != 0) return byClock;
  final byPresence =
      (a.containsKey(field) ? 1 : 0) - (b.containsKey(field) ? 1 : 0);
  if (byPresence != 0) return byPresence;
  return canon(a[field]).compareTo(canon(b[field]));
}

/// Whole-node last-writer-wins for `membership/` and `read/` nodes
/// (`{member|read, hlc, key|url}`): the greater `hlc` wins outright.
Node mergeRegister(Node a, Node b) {
  final byClock = compareHlc(_str(a[kHlcField]), _str(b[kHlcField]));
  if (byClock != 0) return byClock > 0 ? a : b;
  return canon(a).compareTo(canon(b)) >= 0 ? a : b;
}

/// Max-merge for `progress/` nodes: the further position wins outright, so
/// progress never decreases (ReadingProgress.isAheadOf).
Node mergeProgress(Node a, Node b) => compareProgress(a, b) >= 0 ? a : b;

/// Total order on progress nodes: chapterNumber (missing sorts lowest), then
/// page, then readAt, then the canonical JSON as a final tie-breaker.
int compareProgress(Node a, Node b) {
  final byChapter = _num(a['chapterNumber'])
      .compareTo(_num(b['chapterNumber']));
  if (byChapter != 0) return byChapter;
  final byPage = _num(a['page']).compareTo(_num(b['page']));
  if (byPage != 0) return byPage;
  final byTime = (_str(a['readAt']) ?? '').compareTo(_str(b['readAt']) ?? '');
  if (byTime != 0) return byTime;
  return canon(a).compareTo(canon(b));
}

double _num(Object? v) => v is num ? v.toDouble() : double.negativeInfinity;

String? _str(Object? v) => v is String ? v : null;
