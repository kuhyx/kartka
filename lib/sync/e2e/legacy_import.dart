/// The one-time copy of the old plaintext `/kartka` tree into the e2e root.
///
/// When the old root's published revisions differ from the ones last copied
/// (first run, or a not-yet-updated device wrote there since), every old
/// node is merged into the shadow with its namespace's rule. The sync that
/// follows is then a full pull of the e2e root (pushing, sealed, every node
/// the root lacks), and only once it got through are the copied revisions
/// recorded, so a failed sync copies again. The old tree is only ever read
/// ([LegacyTree] cannot write).
library;

import 'package:kartka/sync/e2e/sealed_transport.dart';
import 'package:kartka/sync/merge/merge_rules.dart';
import 'package:kartka/sync/rtdb_transport.dart';
import 'package:kartka/sync/sync_namespaces.dart';
import 'package:kartka/sync/sync_shadow.dart';

/// Merges the old tree when its revisions changed; returns those revisions
/// (for `SyncShadow.legacyRevs` after a full sync), or null when nothing
/// was due.
Future<String?> importLegacy(
  RtdbTransport transport,
  SyncShadow shadow,
  void Function(String path, Node node) merge,
) async {
  final old = transport is SealedTransport ? transport.legacy : null;
  if (old == null) return null;
  final revs = canon(fromRtdb(await old.get('revs')));
  if (shadow.legacyRevs == revs) return null;
  for (final MapEntry(key: ns, value: (depth, _)) in kSyncNamespaces.entries) {
    flattenNodes(ns, await old.get(ns), depth).forEach(merge);
  }
  return revs;
}
