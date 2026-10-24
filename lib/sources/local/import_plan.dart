import 'dart:typed_data';

import 'package:kartka/sources/local/archive_scan.dart';
import 'package:kartka/sources/local/comic_info.dart';
import 'package:kartka/sources/local/natural_sort.dart';

/// Chapter name for images picked loose, outside any folder.
const String looseImagesName = 'Imported pages';

/// One chapter-to-be, decided from picked paths alone (no bytes read yet).
sealed class ImportUnit {
  const new(this.path);

  /// Archive path, or the directory holding a folder chapter's images.
  final String path;
}

/// A CBZ/ZIP file; read with [scanArchive].
final class ArchiveUnit extends ImportUnit {
  /// Creates an archive unit for [path].
  const new(super.path);
}

/// A directory of images; read with [scanFolder].
final class FolderUnit extends ImportUnit {
  /// Creates a folder unit for directory [path].
  const new({
    required String path,
    required this.imagePaths,
    this.comicInfoPath,
  }) : super(path);

  /// The directory's page images, in natural order.
  final List<String> imagePaths;

  /// The directory's own `ComicInfo.xml`, if picked.
  final String? comicInfoPath;
}

/// Groups picked file [paths] into chapters: every archive is one chapter and
/// every directory with images is one chapter. Junk and other files are
/// dropped. Units come back in natural path order.
List<ImportUnit> planImport(Iterable<String> paths) {
  final archives = <String>[];
  final images = <String, List<String>>{};
  final infos = <String, String>{};
  for (final raw in paths) {
    final path = normalizePath(raw);
    if (isJunkPath(path)) continue;
    if (isArchivePath(path)) {
      archives.add(path);
    } else if (isImagePath(path)) {
      (images[dirName(path)] ??= []).add(path);
    } else if (isComicInfoPath(path)) {
      infos[dirName(path)] = path;
    }
  }
  final units = <ImportUnit>[
    for (final a in archives) ArchiveUnit(a),
    for (final MapEntry(:key, :value) in images.entries)
      FolderUnit(
        path: key,
        imagePaths: naturalSorted(value),
        comicInfoPath: infos[key],
      ),
  ];
  return naturalSortedBy(units, (u) => u.path);
}

/// Builds a chapter from a folder [unit] whose image bytes were read into
/// [pages] (same order as [FolderUnit.imagePaths]).
ScannedChapter scanFolder(
  FolderUnit unit,
  List<Uint8List> pages,
  Uint8List? comicInfo,
) => ScannedChapter(
  name: unit.path.isEmpty ? looseImagesName : baseName(unit.path),
  folder: parentName(unit.path),
  info: comicInfo == null ? null : ComicInfo.parseBytes(comicInfo),
  pages: pages,
);
