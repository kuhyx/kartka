import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/sources/suwayomi/suwayomi_extensions.dart';

/// What the user asked to do with one extension.
enum ExtensionAction {
  /// Install from the store.
  install,

  /// Update to the store's version.
  update,

  /// Remove from the server.
  uninstall,
}

/// One extension row with its install / update / uninstall buttons.
class ExtensionTile extends StatelessWidget {
  /// Creates the tile.
  const new({
    required this.extension,
    required this.busy,
    required this.onAction,
    super.key,
  });

  /// The extension shown.
  final SuwayomiExtension extension;

  /// Whether an action on it is running.
  final bool busy;

  /// Runs an action.
  final void Function(ExtensionAction action) onAction;

  @override
  Widget build(BuildContext context) {
    final e = extension;
    final details = [
      e.lang,
      'v${e.versionName}',
      if (e.hasUpdate) 'update available',
      if (e.isObsolete) 'obsolete',
    ].join(' · ');
    return ListTile(
      leading: CircleAvatar(child: Text(e.name.characters.first)),
      title: Text(e.name),
      subtitle: Text(details),
      trailing: busy
          ? const SizedBox.square(
              dimension: AppSpacing.lg,
              child: CircularProgressIndicator(),
            )
          : Wrap(
              spacing: AppSpacing.sm,
              children: [
                if (!e.isInstalled)
                  FilledButton(
                    onPressed: () => onAction(ExtensionAction.install),
                    child: const Text('Install'),
                  ),
                if (e.isInstalled && e.hasUpdate)
                  FilledButton(
                    onPressed: () => onAction(ExtensionAction.update),
                    child: const Text('Update'),
                  ),
                if (e.isInstalled)
                  OutlinedButton(
                    onPressed: () => onAction(ExtensionAction.uninstall),
                    child: const Text('Uninstall'),
                  ),
              ],
            ),
    );
  }
}
