import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/core/ui/snack_mark.dart';
import 'package:kartka/core/ui/spoken_label.dart';
import 'package:kartka/source_health/install/source_installs.dart';
import 'package:kartka/source_health/model/source_health_record.dart';
import 'package:kartka/source_health/ui/health_badge.dart';
import 'package:kartka/source_health/ui/health_icons.dart';

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
    final error = await installs.install(record);
    if (error == null || !context.mounted) return;
    showMark(
      context,
      IconValue(
        Icons.error_outline,
        error,
        semanticLabel: 'Install failed',
        color: statusColors(context).onStatus,
      ),
      error: true,
    );
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
          Icon(
            Icons.report_problem_outlined,
            key: ValueKey('autoinstall-flag-$id'),
            color: Theme.of(context).colorScheme.error,
            semanticLabel: flag,
          ),
        ],
      );
    },
  );

  Widget _button(BuildContext context, String id) =>
      switch (installs.actionOf(record)) {
        SourceAction.open => IconButton.outlined(
          key: ValueKey('open-$id'),
          style: _size,
          icon: const Icon(Icons.open_in_new, semanticLabel: 'Open'),
          onPressed: () => installs.open(context, id),
        ),
        SourceAction.install => IconButton.filledTonal(
          key: ValueKey('install-$id'),
          style: _size,
          icon: const Icon(Icons.download, semanticLabel: 'Install'),
          onPressed: () => _install(context),
        ),
        SourceAction.installing => IconButton.filledTonal(
          key: ValueKey('installing-$id'),
          style: _size,
          icon: const SpokenLabel(
            semanticLabel: 'Installing',
            child: SizedBox.square(
              dimension: AppSpacing.md,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          onPressed: null,
        ),
      };

  static final ButtonStyle _size = IconButton.styleFrom(
    minimumSize: const Size.square(48),
  );
}
