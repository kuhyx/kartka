import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/backup_import/import_controller.dart';
import 'package:kartka/backup_import/import_preview.dart';

/// More → "Import SY backup": choose a `.tachibk`, review, import.
class ImportScreen extends StatelessWidget {
  /// Creates the screen around [controller].
  const ImportScreen({required this.controller, super.key});

  /// Drives the flow.
  final ImportController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Import SY backup')),
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
        return [
          Text(
            'Pick a TachiyomiSY backup (.tachibk). You get a summary first; '
            'nothing is written until you confirm. Importing the same backup '
            'again changes nothing.',
            style: text.bodyMedium,
          ),
          gap,
          _action('Choose backup file', c.pick),
        ];
      case ImportPhase.loading:
        return [
          const LinearProgressIndicator(),
          gap,
          Text('Reading ${c.fileName ?? 'backup'}', style: text.bodyMedium),
        ];
      case ImportPhase.preview:
        return [
          Text(c.fileName ?? '', style: text.titleMedium),
          ImportPreview(c.plan!.summary),
          gap,
          _action('Import ${c.plan!.summary.entries} entries', c.runImport),
          gap,
          OutlinedButton(
            onPressed: c.pick,
            child: const Text('Choose another file'),
          ),
        ];
      case ImportPhase.importing:
        final (done, total) = c.progress;
        return [
          LinearProgressIndicator(value: total == 0 ? null : done / total),
          gap,
          Text('Imported $done of $total entries', style: text.bodyMedium),
        ];
      case ImportPhase.done:
        return [
          ImportOutcome(c.result!),
          gap,
          OutlinedButton(onPressed: c.reset, child: const Text('Done')),
        ];
      case ImportPhase.failed:
        return [
          Text(
            c.error ?? 'Import failed',
            style: text.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
          gap,
          _action('Try again', c.reset),
        ];
    }
  }

  Widget _action(String label, VoidCallback onTap) =>
      FilledButton(onPressed: onTap, child: Text(label));
}
