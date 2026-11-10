import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/sources/suwayomi/suwayomi_extensions.dart';

const _tap = Size.square(48);

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
    final colors = Theme.of(context).colorScheme;
    // Language code and version are content; the update / obsolete flags
    // are glyphs after them.
    return ListTile(
      leading: CircleAvatar(child: Text(e.name.characters.first)),
      title: Text(e.name),
      subtitle: Row(
        children: [
          Flexible(child: Text('${e.lang} · v${e.versionName}')),
          if (e.hasUpdate) ...[
            const SizedBox(width: AppSpacing.xs),
            Icon(
              Icons.new_releases_outlined,
              size: 16,
              color: colors.primary,
              semanticLabel: 'update available',
            ),
          ],
          if (e.isObsolete) ...[
            const SizedBox(width: AppSpacing.xs),
            Icon(
              Icons.warning_amber,
              size: 16,
              color: colors.error,
              semanticLabel: 'obsolete',
            ),
          ],
        ],
      ),
      trailing: busy
          ? const SizedBox.square(
              dimension: AppSpacing.lg,
              child: CircularProgressIndicator(),
            )
          : Wrap(
              spacing: AppSpacing.sm,
              children: [
                if (!e.isInstalled)
                  IconButton.filled(
                    style: IconButton.styleFrom(minimumSize: _tap),
                    onPressed: () => onAction(ExtensionAction.install),
                    icon: const Icon(Icons.download, semanticLabel: 'Install'),
                  ),
                if (e.isInstalled && e.hasUpdate)
                  IconButton.filled(
                    style: IconButton.styleFrom(minimumSize: _tap),
                    onPressed: () => onAction(ExtensionAction.update),
                    icon: const Icon(Icons.upgrade, semanticLabel: 'Update'),
                  ),
                if (e.isInstalled)
                  IconButton.outlined(
                    style: IconButton.styleFrom(minimumSize: _tap),
                    onPressed: () => onAction(ExtensionAction.uninstall),
                    icon: const Icon(
                      Icons.delete_outline,
                      semanticLabel: 'Uninstall',
                    ),
                  ),
              ],
            ),
    );
  }
}
