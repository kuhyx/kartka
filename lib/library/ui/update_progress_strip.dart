import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/library/ports.dart';

/// A thin bar and "12/87" while [updater] runs; nothing when idle.
class UpdateProgressStrip extends StatelessWidget {
  /// Shows [updater]'s progress.
  const new(this.updater, {super.key});

  /// The shared update-all run.
  final LibraryUpdater updater;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: updater,
    builder: (context, _) {
      final p = updater.progress;
      if (p == null) return const SizedBox.shrink();
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LinearProgressIndicator(
            value: p.total == 0 ? null : p.done / p.total,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            child: Text(
              '${p.done}/${p.total}',
              semanticsLabel: p.label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      );
    },
  );
}
