import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/core/redact.dart';
import 'package:kartka/platform/platform.dart';
import 'package:kartka/sources/local/local_library.dart';

enum _Kind { archives, folder }

/// "Import local files" settings tile: pick CBZ/ZIP archives or a folder of
/// images through the platform [FilePicker] and import them into [library].
class ImportLocalTile extends StatefulWidget {
  /// Creates the tile.
  const new({required this.library, required this.picker, super.key});

  /// Where imports land.
  final LocalLibrary library;

  /// Platform file picker (Android files, web bytes).
  final FilePicker picker;

  @override
  State<ImportLocalTile> createState() => _ImportLocalTileState();
}

class _ImportLocalTileState extends State<ImportLocalTile> {
  bool _busy = false;

  Future<void> _start() async {
    final kind = await showDialog<_Kind>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Import local files'),
        children: [
          _option(
            context,
            _Kind.archives,
            Icons.archive_outlined,
            'CBZ / ZIP archives',
          ),
          _option(
            context,
            _Kind.folder,
            Icons.folder_outlined,
            'Folder of images',
          ),
        ],
      ),
    );
    if (kind == null) return;
    final files = switch (kind) {
      _Kind.archives => await widget.picker.pickFiles(
        extensions: const ['cbz', 'zip'],
        multiple: true,
      ),
      _Kind.folder => await widget.picker.pickDirectory(),
    };
    if (files.isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      final report = await widget.library.importFiles(files);
      if (!mounted) return;
      if (report.errors.isEmpty) {
        showToast(context, report.summary);
      } else {
        showError(context, report.summary);
      }
    } on Object catch (e) {
      if (mounted) showError(context, redactUrlQueries('Import failed: $e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _option(
    BuildContext context,
    _Kind kind,
    IconData icon,
    String label,
  ) => SimpleDialogOption(
    onPressed: () => Navigator.of(context).pop(kind),
    child: Row(
      children: [
        Icon(icon),
        const SizedBox(width: AppSpacing.md),
        Text(label),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => ListTile(
    leading: const Icon(Icons.folder_zip_outlined),
    title: const Text('Import local files'),
    subtitle: const Text('CBZ / ZIP archives or a folder of images'),
    trailing: _busy
        ? const SizedBox.square(
            dimension: AppSpacing.lg,
            child: CircularProgressIndicator(),
          )
        : null,
    enabled: !_busy,
    onTap: _start,
  );
}
