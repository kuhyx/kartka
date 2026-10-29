import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/source_health/install/source_installs.dart';
import 'package:kartka/source_health/model/source_health_record.dart';

/// Install / Installing… / Open for one source, on its card and detail page.
/// A failed install shows a snackbar with the redacted reason.
class SourceActionButton extends StatelessWidget {
  /// Creates the button for [record].
  const new({required this.record, required this.installs, super.key});

  /// The source.
  final SourceHealthRecord record;

  /// Shared install state.
  final SourceInstalls installs;

  Future<void> _install(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final error = await installs.install(record);
    if (error == null) return;
    messenger.showSnackBar(SnackBar(content: Text('Install failed: $error')));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: installs,
    builder: (context, _) {
      final id = record.id;
      final button = _button(context, id);
      final flag = installs.flagOf(id);
      if (flag == null) return button;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        spacing: AppSpacing.xs,
        children: [
          button,
          Text(
            flag,
            key: ValueKey('autoinstall-flag-$id'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      );
    },
  );

  Widget _button(BuildContext context, String id) =>
      switch (installs.actionOf(record)) {
        SourceAction.open => OutlinedButton.icon(
          key: ValueKey('open-$id'),
          icon: const Icon(Icons.open_in_new),
          label: const Text('Open'),
          onPressed: () => installs.open(context, id),
        ),
        SourceAction.install => FilledButton.tonalIcon(
          key: ValueKey('install-$id'),
          icon: const Icon(Icons.download),
          label: const Text('Install'),
          onPressed: () => _install(context),
        ),
        SourceAction.installing => FilledButton.tonalIcon(
          key: ValueKey('installing-$id'),
          icon: const SizedBox.square(
            dimension: AppSpacing.md,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          label: const Text('Installing…'),
          onPressed: null,
        ),
      };
}
