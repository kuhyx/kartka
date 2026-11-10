import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/backup_import/import_controller.dart';
import 'package:kartka/backup_import/import_preview.dart';
import 'package:kartka/core/redact.dart';

/// More → "Import SY backup": choose a `.tachibk`, review, import.
class ImportScreen extends StatelessWidget {
  /// Creates the screen around [controller].
  const new({required this.controller, super.key});

  /// Drives the flow.
  final ImportController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Icon(
          Icons.file_upload_outlined,
          semanticLabel: 'Import SY backup',
        ),
      ),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: _children(context),
        ),
      ),
    );
  }

  List<Widget> _children(BuildContext context) {
    final c = controller;
    const gap = SizedBox(height: AppSpacing.md);
    final text = Theme.of(context).textTheme;
    switch (c.phase) {
      case ImportPhase.idle:
        return [_action(Icons.folder_open, 'Choose backup file', c.pick)];
      case ImportPhase.loading:
        return [
          const LinearProgressIndicator(),
          gap,
          Text(c.fileName ?? '', style: text.bodyMedium),
        ];
      case ImportPhase.preview:
        final entries = c.plan!.summary.entries;
        return [
          Text(c.fileName ?? '', style: text.titleMedium),
          ImportPreview(
            c.plan!.summary,
            unavailable: c.unavailable,
            bindTrackers: c.bindsTrackers,
          ),
          gap,
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: _minSize),
            onPressed: c.runImport,
            icon: const Icon(Icons.download),
            label: Text('$entries', semanticsLabel: 'Import $entries entries'),
          ),
          gap,
          OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: _minSize),
            onPressed: c.pick,
            child: const Icon(
              Icons.folder_open,
              semanticLabel: 'Choose another file',
            ),
          ),
        ];
      case ImportPhase.importing:
        final (done, total) = c.progress;
        return [
          LinearProgressIndicator(value: total == 0 ? null : done / total),
          gap,
          Text(
            '$done / $total',
            style: text.bodyMedium,
            semanticsLabel: 'Imported $done of $total entries',
          ),
        ];
      case ImportPhase.done:
        return [
          ImportOutcome(c.result!),
          gap,
          OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: _minSize),
            onPressed: c.reset,
            child: const Icon(Icons.check, semanticLabel: 'Done'),
          ),
        ];
      case ImportPhase.failed:
        // The decoder's sentence is app-written: spoken, never painted.
        return [
          Icon(
            Icons.error_outline,
            size: 48,
            color: Theme.of(context).colorScheme.error,
            semanticLabel: redactUrlQueries(c.error ?? 'Import failed'),
          ),
          gap,
          _action(Icons.refresh, 'Try again', c.reset),
        ];
    }
  }

  static const _minSize = Size.square(48);

  Widget _action(IconData icon, String spoken, VoidCallback onTap) =>
      FilledButton(
        style: FilledButton.styleFrom(minimumSize: _minSize),
        onPressed: onTap,
        child: Icon(icon, semanticLabel: spoken),
      );
}
