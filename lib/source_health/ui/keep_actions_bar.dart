import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/core/ui/spoken_label.dart';
import 'package:kartka/source_health/install/auto_install_state.dart';
import 'package:kartka/source_health/install/keep_reconciler.dart';
import 'package:kartka/source_health/ui/health_badge.dart';
import 'package:kartka/source_health/ui/health_icons.dart';

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
      builder: (context, _) => _row(context, reconciler.state),
    );
  }

  Widget _row(BuildContext context, AutoInstallState? state) {
    final migrate = onMigrate;
    final status = state?.status;
    if (status == null && migrate == null) return const SizedBox.shrink();
    return Row(
      spacing: AppSpacing.sm,
      children: [
        Expanded(
          child: status == null
              ? const SizedBox.shrink()
              : _status(context, state!, status),
        ),
        if (migrate != null)
          IconButton.outlined(
            key: const Key('migrate-better'),
            style: IconButton.styleFrom(minimumSize: const Size.square(48)),
            icon: const Icon(
              Icons.swap_horiz,
              semanticLabel: 'Migrate to better sources',
            ),
            onPressed: () => migrate(context),
          ),
      ],
    );
  }

  /// Glyph + count per non-zero total, spoken as [status].
  Widget _status(BuildContext context, AutoInstallState s, String status) {
    final c = s.counts;
    final danger = statusColors(context).danger;
    return SpokenLabel(
      key: const Key('autoinstall-status'),
      semanticLabel: status,
      child: ExcludeSemantics(
        child: Wrap(
          spacing: AppSpacing.md,
          children: [
            for (final (icon, n, color) in [
              (Icons.download_done, c.installed, null),
              (Icons.report_problem_outlined, c.tests, danger),
              (Icons.error_outline, c.installs, danger),
            ])
              if (n > 0) IconValue(icon, '$n', semanticLabel: '', color: color),
          ],
        ),
      ),
    );
  }
}
