/// End-to-end encryption of the kartka RTDB tree (DOCS-contracts §4, §12).
///
/// Everything lives under `/kartka-e2e` (crdt_sync's [E2eLayout] of the old
/// `/kartka` root, which is never written again nor deleted). Every synced
/// node and every error report is stored as
/// `{p: <sealed JSON>, h: <newest Hlc>, d: true?}`: the node's field names
/// and values are sealed with crdt_sync's [E2eCipher]; the AAD binds the
/// node path and both clear fields (`<root>/<path>#<d>#<h>`), so a node can
/// be neither moved nor have its clock or tombstone edited. Node paths,
/// `revs/` and `log/` (peers subtract integer revisions) and the evaluator's
/// public `source_health*` stay clear. Any other write is refused, so a new
/// node cannot go out in plaintext by accident; a node that does not open
/// (plaintext, tampered, another key) reads as absent.
library;

import 'dart:convert';

import 'package:crdt_sync/crdt_sync.dart' show E2eCipher, E2eLayout;
import 'package:kartka/sync/merge/merge_rules.dart';
import 'package:kartka/sync/rtdb_transport.dart';
import 'package:kartka/sync/sync_namespaces.dart';

/// The pre-e2e root: read by the one-time copy, never written or deleted.
const String kLegacyRoot = 'kartka';

/// Where kartka's data lives now: `kartka-e2e`, header at `kartka-e2e/e2e`.
final E2eLayout kE2eLayout = E2eLayout.of(kLegacyRoot);

/// Sealed payload field of a stored node.
const String kSealedField = 'p';

/// Clear newest-Hlc field of a stored node.
const String kNewestField = 'h';

/// Clear tombstone field of a stored node (present only when true).
const String kTombstoneField = 'd';

/// Top-level children stored as they are.
const Set<String> kClearRoots = {
  'revs',
  'log',
  'source_health',
  'source_health_meta',
};

/// A write (or read) the layout has no rule for.
class E2eLayoutError implements Exception {
  /// Creates the error.
  const new(this.message);

  /// What was refused.
  final String message;

  @override
  String toString() => 'E2eLayoutError: $message';
}

/// Key depth of the sealed namespace [ns], or null when it is not one.
int? sealedDepth(String ns) => ns == 'errors' ? 2 : kSyncNamespaces[ns]?.$1;

/// Whether [node] in namespace [ns] is a tombstone (a removal).
bool isTombstone(String ns, Node node) => switch (ns) {
  'library' || 'categories' => node['removed'] == true,
  'membership' => node['member'] == false,
  'read' => node['read'] == false,
  'settings' => !node.containsKey('value') && !node.containsKey('enc'),
  _ => false,
};

/// The AAD of the node at [rel] with clear fields [deleted] and [newest].
String nodeAad(String rel, {required bool deleted, String? newest}) =>
    '${kE2eLayout.prefix}/$rel#${deleted ? 1 : 0}#${newest ?? ''}';

/// Read-only access to the old `/kartka` tree: nothing here can write.
class LegacyTree {
  /// Reads through [_transport] (rooted at [kLegacyRoot]).
  new(this._transport);

  final RtdbTransport _transport;

  /// The decoded JSON at [path] under the old root.
  Future<Object?> get(String path) => _transport.get(path);
}

/// An [RtdbTransport] that seals every node it writes to [inner] (rooted at
/// `kartka-e2e`) and opens every node it reads.
class SealedTransport implements RtdbTransport {
  /// Seals with [cipher] (built with `acceptPlaintext: false`).
  new(this.inner, this.cipher, {this.legacy});

  /// The transport on the e2e root.
  final RtdbTransport inner;

  /// The key's cipher.
  final E2eCipher cipher;

  /// The old plaintext tree, for the one-time copy.
  final LegacyTree? legacy;

  @override
  Future<Object?> get(String path) async {
    final parts = _parts(path);
    final depth = _check(parts, write: false);
    final raw = await inner.get(path);
    if (depth == null) return raw;
    return await _open(parts, fromRtdb(raw), depth);
  }

  @override
  Future<void> patch(Map<String, Object?> updates) async {
    final sealed = <String, Object?>{};
    for (final MapEntry(:key, :value) in updates.entries) {
      final parts = _parts(key);
      final depth = _check(parts, write: true);
      sealed[key] = depth == null ? value : await _seal(parts, value);
    }
    await inner.patch(sealed);
  }

  /// The namespace depth for a sealed path (null: clear); throws for a
  /// path the layout has no rule for.
  static int? _check(List<String> parts, {required bool write}) {
    if (parts.isEmpty) throw const E2eLayoutError('the whole root');
    if (kClearRoots.contains(parts.first)) return null;
    final depth = sealedDepth(parts.first);
    final rel = parts.join('/');
    if (depth == null) throw E2eLayoutError('no rule for $rel');
    if (parts.length > depth + 1) throw E2eLayoutError('inside a node: $rel');
    if (write && parts.length != depth + 1) {
      throw E2eLayoutError('write above a node: $rel');
    }
    return depth;
  }

  Future<Object?> _seal(List<String> parts, Object? value) async {
    if (value == null) return null;
    if (value is! Map<String, Object?>) {
      throw E2eLayoutError('not a node at ${parts.join('/')}');
    }
    final node = _pruned(value);
    if (node == null) return null;
    final deleted = isTombstone(parts.first, node);
    final newest = newestClock(node, null);
    final aad = nodeAad(parts.join('/'), deleted: deleted, newest: newest);
    return <String, Object?>{
      kSealedField: await cipher.seal(jsonEncode(node), path: aad),
      kNewestField: ?newest,
      if (deleted) kTombstoneField: true,
    };
  }

  Future<Object?> _open(List<String> parts, Object? value, int depth) async {
    if (parts.length == depth + 1) return await _openNode(parts, value);
    if (value is! Map<String, Object?>) return null;
    final out = <String, Object?>{};
    for (final MapEntry(:key, value: child) in value.entries) {
      final opened = await _open([...parts, key], child, depth);
      if (opened != null) out[key] = opened;
    }
    return out;
  }

  Future<Node?> _openNode(List<String> parts, Object? value) async {
    if (value is! Map<String, Object?>) return null;
    final blob = value[kSealedField];
    final newest = value[kNewestField];
    if (blob is! String || (newest != null && newest is! String)) return null;
    try {
      final text = await cipher.open(
        blob,
        path: nodeAad(
          parts.join('/'),
          deleted: value[kTombstoneField] == true,
          newest: newest as String?,
        ),
      );
      return switch (jsonDecode(text)) {
        final Map<String, Object?> node => node,
        _ => null,
      };
    } on FormatException {
      // E2eDecryptError is one: plaintext, tampered, moved or another key.
      return null;
    }
  }

  static List<String> _parts(String path) =>
      path.split('/').where((s) => s.isNotEmpty).toList();

  // As RTDB would keep it: no null members, no empty objects.
  static Node? _pruned(Node node) {
    Object? prune(Object? v) {
      if (v is! Map) return v;
      final out = <String, Object?>{
        for (final e in v.entries) '${e.key}': ?prune(e.value),
      };
      return out.isEmpty ? null : out;
    }

    return prune(node) as Node?;
  }
}
