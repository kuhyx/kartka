import 'package:file_picker/file_picker.dart' as fp;
import 'package:kartka/platform/file_picker.dart';

/// [FilePicker] on `package:file_picker` (Android and web).
///
/// Directory picking differs per platform (Android lists a real path; web
/// needs `webkitdirectory`), so it is injected.
class PluginFilePicker implements FilePicker {
  /// Uses the plugin for files and [_pickDirectory] for folders.
  new({required this._pickDirectory});

  final Future<List<PickedFile>> Function() _pickDirectory;

  @override
  Future<List<PickedFile>> pickFiles({
    List<String> extensions = const [],
    bool multiple = false,
  }) async {
    final type = extensions.isEmpty ? fp.FileType.any : fp.FileType.custom;
    final allowed = extensions.isEmpty ? null : extensions;
    final files = multiple
        ? await fp.FilePicker.pickFiles(type: type, allowedExtensions: allowed)
        : [
            ?await fp.FilePicker.pickFile(
              type: type,
              allowedExtensions: allowed,
            ),
          ];
    return [
      for (final f in files) PickedFile(name: f.name, read: f.readAsBytes),
    ];
  }

  @override
  Future<List<PickedFile>> pickDirectory() => _pickDirectory();
}
