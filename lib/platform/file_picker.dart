import 'dart:typed_data';

/// Lets the user choose files or a folder to import (DOCS-contracts §11).
///
/// Named `FilePicker` per the contract; `package:file_picker` has a class of
/// the same name, so only `lib/platform/` touches that package.
abstract interface class FilePicker {
  /// Files with one of [extensions] (no dot, e.g. `cbz`; empty = any).
  /// Empty when the user cancels.
  Future<List<PickedFile>> pickFiles({
    List<String> extensions = const [],
    bool multiple = false,
  });

  /// Every file under a folder the user picks (web: `webkitdirectory`).
  /// Empty when the user cancels.
  Future<List<PickedFile>> pickDirectory();
}

/// One picked file; bytes are read lazily (CBZs can be large).
class PickedFile {
  /// Creates a picked file read by [read].
  const new({required this.name, required this.read, this.relativePath});

  /// File name with extension.
  final String name;

  /// Path inside the picked folder (`Series/ch1.cbz`), `null` for
  /// [FilePicker.pickFiles].
  final String? relativePath;

  /// Reads the whole file; prefer [readBytes].
  final Future<Uint8List> Function() read;

  /// Reads the whole file.
  Future<Uint8List> readBytes() => read();
}
