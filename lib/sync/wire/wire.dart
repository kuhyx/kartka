/// Model <-> RTDB node mapping for the synced namespaces (contracts §4, §12,
/// §13). Paths are relative to `/kartka`.
library;

import 'dart:math';

import 'package:crdt_sync/crdt_sync.dart' show Hlc;
import 'package:kartka/core/models/json_fields.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/sync/merge/merge_rules.dart';
import 'package:kartka/sync/rtdb_transport.dart';

/// `library/<mangaKeyHash>`.
String libraryPath(MangaKey key) => 'library/${mangaKeyHash(key)}';

/// `categories/<id>`, with the id escaped into one RTDB key.
String categoryPath(String id) => 'categories/${rtdbKey(id)}';

/// `membership/<mangaKeyHash>/<categoryId>`.
String membershipPath(MangaKey key, String categoryId) =>
    'membership/${mangaKeyHash(key)}/${rtdbKey(categoryId)}';

/// `progress/<mangaKeyHash>`.
String progressPath(MangaKey key) => 'progress/${mangaKeyHash(key)}';

/// `read/<mangaKeyHash>/<chapterUrlHash>`.
String readPath(MangaKey key, String chapterUrl) =>
    'read/${mangaKeyHash(key)}/${mangaKeyHash(chapterUrl)}';

/// The flat synced values of a library entry (`updatedAt` is derived).
Map<String, Object?> libraryValues(LibraryEntry e) => {
  'key': e.key,
  'sourceId': e.sourceId,
  'mangaUrl': e.mangaUrl,
  'title': e.title,
  'coverUrl': e.coverUrl,
  'addedAt': writeDate(e.addedAt),
  'removed': e.removed,
};

/// The flat synced values of a category.
Map<String, Object?> categoryValues(Category c) => {
  'id': c.id,
  'name': c.name,
  'order': c.order,
  'removed': c.removed,
};

/// A node holding only the fields of [values] that differ from [old], each
/// stamped with [hlc]; null when nothing changed. Nulls are left out (RTDB
/// drops them) but still stamped, so clearing a field wins later merges.
Node? stampChanges(Node? old, Map<String, Object?> values, String hlc) {
  final out = <String, Object?>{};
  final clocks = <String, Object?>{};
  final oldClocks = old?[kHlcField];
  for (final MapEntry(:key, :value) in values.entries) {
    final unchanged =
        old != null &&
        canon(old[key]) == canon(value) &&
        oldClocks is Map &&
        oldClocks.containsKey(key);
    if (unchanged) continue;
    if (value != null) out[key] = value;
    clocks[key] = hlc;
  }
  if (clocks.isEmpty) return null;
  return {...out, kHlcField: clocks};
}

/// `updatedAt` per §12: the greatest field Hlc's wall time.
DateTime maxHlcTime(Node node) {
  var ms = 0;
  if (node[kHlcField] case final Map<Object?, Object?> clocks) {
    for (final c in clocks.values.whereType<String>()) {
      try {
        ms = max(ms, Hlc.fromStr(c).wallTimeMs);
      } on FormatException {
        continue;
      }
    }
  }
  return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
}

/// A strictly increasing local timestamp from [h], for the local repos'
/// own LWW: the counter becomes microseconds so same-millisecond ticks still
/// order.
DateTime localStamp(Hlc h) => DateTime.fromMicrosecondsSinceEpoch(
  h.wallTimeMs * 1000 + min(h.counter, 999),
  isUtc: true,
);

/// The entry in a `library/` node, or null when required fields are missing.
LibraryEntry? libraryFromNode(Node n) {
  final key = n['key'];
  final title = n['title'];
  final addedAt = DateTime.tryParse('${n['addedAt']}');
  if (key is! String || title is! String || addedAt == null) return null;
  final cut = key.indexOf('|');
  return LibraryEntry(
    key: key,
    sourceId: n['sourceId'] as String? ?? key.substring(0, max(cut, 0)),
    mangaUrl: n['mangaUrl'] as String? ?? key.substring(cut + 1),
    title: title,
    coverUrl: n['coverUrl'] as String?,
    addedAt: addedAt,
    updatedAt: maxHlcTime(n),
    removed: n['removed'] == true,
  );
}

/// The category in a `categories/` node at [path], or null when incomplete.
Category? categoryFromNode(String path, Node n) {
  final name = n['name'];
  final order = n['order'];
  if (name is! String || order is! num) return null;
  return Category(
    id: n['id'] as String? ?? rtdbKeyDecode(path.split('/').last),
    name: name,
    order: order.toInt(),
    updatedAt: maxHlcTime(n),
    removed: n['removed'] == true,
  );
}

/// The progress in a `progress/` node, or null when malformed.
ReadingProgress? progressFromNode(Node n) {
  final (key, url, number, page) = (
    n['key'],
    n['chapterUrl'],
    n['chapterNumber'],
    n['page'],
  );
  final readAt = DateTime.tryParse('${n['readAt']}');
  // A hand-edited or foreign node is skipped rather than breaking the tick.
  if (key is! String || url is! String || number is! num || page is! num) {
    return null;
  }
  if (readAt == null) return null;
  return ReadingProgress(
    key: key,
    chapterUrl: url,
    chapterNumber: number.toDouble(),
    page: page.toInt(),
    readAt: readAt,
    pageCount: switch (n['pageCount']) {
      final num c => c.toInt(),
      _ => null,
    },
  );
}
