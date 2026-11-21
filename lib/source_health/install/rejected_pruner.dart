import 'package:kartka/source_health/install/install_ports.dart';

/// Removes every installed extension whose sources were all rejected for
/// good (meta `rejectedIds`, score <= 0.65) and that no library entry uses
/// (note 53c9b0fa item 2: "remove it"). Needs an [installer] that lists
/// package sources and removes; any other side, or a failed read, removes
/// nothing and the next run tries again. Returns the removed packages.
Future<List<String>> pruneRejected(
  Object? installer, {
  required Set<String> rejected,
  required Set<String> library,
}) async {
  if (rejected.isEmpty ||
      installer is! ExtensionSourceLister ||
      installer is! ExtensionRemover) {
    return const [];
  }
  final removed = <String>[];
  try {
    final sources = await installer.packageSources();
    for (final MapEntry(key: pkg, value: ids) in sources.entries) {
      if (ids.isEmpty || !rejected.containsAll(ids)) continue;
      if (ids.any(library.contains)) continue;
      await (installer as ExtensionRemover).removeExtension(pkg);
      removed.add(pkg);
    }
  } on Object {
    return removed;
  }
  return removed;
}
