import 'dart:io';

import 'package:kartka/platform/file_picker.dart';
import 'package:path/path.dart' as p;

/// Every file under [root] as [PickedFile]s with `/`-separated relative
/// paths, sorted; empty for a `null` root (the user cancelled).
Future<List<PickedFile>> listDirectoryFiles(String? root) async {
  if (root == null) return [];
  final files = [
    await for (final e in Directory(root).list(recursive: true))
      if (e is File) e,
  ];
  final picked = [
    for (final f in files)
      PickedFile(
        name: p.basename(f.path),
        relativePath: p.split(p.relative(f.path, from: root)).join('/'),
        read: f.readAsBytes,
      ),
  ]..sort((a, b) => a.relativePath!.compareTo(b.relativePath!));
  return picked;
}
