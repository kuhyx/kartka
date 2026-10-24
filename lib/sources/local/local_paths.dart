/// Path helpers for archive entries and picked files. All paths are treated
/// as POSIX after [normalizePath]; nothing here touches a filesystem.
library;

const Set<String> _imageExtensions = {
  'jpg',
  'jpeg',
  'png',
  'webp',
  'gif',
  'avif',
  'bmp',
};

const Set<String> _archiveExtensions = {'cbz', 'zip'};

/// Converts Windows separators to `/`.
String normalizePath(String path) => path.replaceAll(r'\', '/');

String _extension(String path) {
  final base = baseName(path);
  final dot = base.lastIndexOf('.');
  return dot <= 0 ? '' : base.substring(dot + 1).toLowerCase();
}

/// Last path segment.
String baseName(String path) => normalizePath(path).split('/').last;

/// File name without its last extension.
String fileStem(String path) {
  final base = baseName(path);
  final dot = base.lastIndexOf('.');
  return dot <= 0 ? base : base.substring(0, dot);
}

/// Directory part of [path] (`''` at the top level).
String dirName(String path) {
  final p = normalizePath(path);
  final slash = p.lastIndexOf('/');
  return slash < 0 ? '' : p.substring(0, slash);
}

/// Name of the directory directly containing [path], or `null` at top level.
String? parentName(String path) {
  final dir = dirName(path);
  return dir.isEmpty ? null : baseName(dir);
}

/// Whether [path] names a page image Kartka can show.
bool isImagePath(String path) => _imageExtensions.contains(_extension(path));

/// Whether [path] names a CBZ/ZIP archive.
bool isArchivePath(String path) =>
    _archiveExtensions.contains(_extension(path));

/// OS metadata that must never become a page: `__MACOSX/`, dotfiles
/// (`._x.jpg`, `.DS_Store`) and `Thumbs.db`.
bool isJunkPath(String path) => normalizePath(path)
    .split('/')
    .any(
      (s) =>
          s == '__MACOSX' ||
          s.startsWith('.') ||
          s.toLowerCase() == 'thumbs.db',
    );
