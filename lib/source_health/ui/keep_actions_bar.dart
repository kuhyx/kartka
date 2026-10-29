import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/source_health/install/keep_reconciler.dart';

/// The Sources tab's Keep row: the auto-install's quiet one-line status
/// (when it has one) and "Migrate to better sources" (when wired).
class KeepActionsBar extends StatelessWidget {
  /// Creates the row; it shows nothing when neither part applies.
  const new({this.autoInstall, this.onMigrate, super.key});

  /// The Keep auto-install whose status is shown.
  final KeepReconciler? autoInstall;

  /// Opens the "Migrate to better sources" screen.
  final void Function(BuildContext context)? onMigrate;

  @override
  Widget build(BuildContext context) {
    final reconciler = autoInstall;
    if (reconciler == null) return _row(context, null);
    return ListenableBuilder(
      listenable: reconciler,
      builder: (context, _) => _row(context, reconciler.status),
    );
  }

  Widget _row(BuildContext context, String? status) {
    final migrate = onMigrate;
    if (status == null && migrate == null) return const SizedBox.shrink();
    return Row(
      spacing: AppSpacing.sm,
      children: [
        Expanded(
          child: status == null
              ? const SizedBox.shrink()
              : Text(
                  status,
                  key: const Key('autoinstall-status'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
        ),
        if (migrate != null)
          OutlinedButton.icon(
            key: const Key('migrate-better'),
            icon: const Icon(Icons.swap_horiz),
            label: const Text('Migrate to better sources'),
            onPressed: () => migrate(context),
          ),
      ],
    );
  }
}
