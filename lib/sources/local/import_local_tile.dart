import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/core/redact.dart';
import 'package:kartka/core/ui/snack_mark.dart';
import 'package:kartka/core/ui/spoken_label.dart';
import 'package:kartka/platform/platform.dart';
import 'package:kartka/sources/local/local_library.dart';

enum _Kind { archives, folder }

/// Spoken name of the folder option.
const _folder = 'Folder of images';

/// An import outcome as glyphs and counts, its sentence spoken only:
/// chapters imported, the manga they went into, and files that failed.
class ImportReportMark extends StatelessWidget {
  /// Shows [report].
  const new(this.report, {super.key});

  /// The outcome shown.
  final ImportReport report;

  @override
  Widget build(BuildContext context) => SpokenLabel(
    semanticLabel: report.summary,
    child: ExcludeSemantics(
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline),
          const SizedBox(width: AppSpacing.sm),
          Text('${report.chapters}'),
          const SizedBox(width: AppSpacing.md),
          const Icon(Icons.collections_bookmark_outlined),
          const SizedBox(width: AppSpacing.sm),
          Text('${report.mangaUrls.length}'),
          if (report.errors.isNotEmpty) ...[
            const SizedBox(width: AppSpacing.md),
            const Icon(Icons.error_outline),
            const SizedBox(width: AppSpacing.sm),
            Text('${report.errors.length}'),
          ],
        ],
      ),
    ),
  );
}

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
        title: const Icon(
          Icons.folder_zip_outlined,
          size: 32,
          semanticLabel: 'Import local files',
        ),
        children: [
          _option(
            context,
            _Kind.archives,
            Icons.archive_outlined,
            'CBZ / ZIP archives',
          ),
          _option(context, _Kind.folder, Icons.folder_outlined, _folder),
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
      showMark(
        context,
        ImportReportMark(report),
        error: report.errors.isNotEmpty,
      );
    } on Object catch (e) {
      // The error itself is content; only the "Import failed" prefix went.
      if (mounted) showError(context, redactUrlQueries('$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _option(
    BuildContext context,
    _Kind kind,
    IconData icon,
    String semanticLabel,
  ) => SimpleDialogOption(
    onPressed: () => Navigator.of(context).pop(kind),
    child: Icon(icon, size: 48, semanticLabel: semanticLabel),
  );

  @override
  Widget build(BuildContext context) => ListTile(
    leading: const Icon(
      Icons.folder_zip_outlined,
      semanticLabel: 'Import local files: CBZ / ZIP archives or a folder',
    ),
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
