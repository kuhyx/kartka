import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/core/redact.dart';
import 'package:kartka/core/ui/spoken_label.dart';
import 'package:kartka/plugins/runtime/plugin_index.dart';
import 'package:kartka/plugins/runtime/plugin_languages.dart';
import 'package:kartka/plugins/runtime/plugin_manager.dart';
import 'package:kartka/plugins/runtime/plugin_store.dart';

/// Minimum tap target of an icon-only button.
const _tap = Size.square(48);

/// Text field plus button that adds a repo URL.
class AddRepoRow extends StatelessWidget {
  /// Creates the row.
  const new({
    required this.controller,
    required this.busy,
    required this.onAdd,
    super.key,
  });

  /// Holds the typed URL.
  final TextEditingController controller;

  /// True while the index is being validated.
  final bool busy;

  /// Called when the user submits.
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
    child: Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.link, semanticLabel: 'Repository URL'),
            ),
            onSubmitted: (_) => onAdd(),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        if (busy)
          const SizedBox.square(
            dimension: AppSpacing.lg,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          IconButton(
            style: IconButton.styleFrom(minimumSize: _tap),
            icon: const Icon(Icons.add, semanticLabel: 'Add repository'),
            onPressed: onAdd,
          ),
      ],
    ),
  );
}

/// Everything the repos offer, with install / update buttons.
class AvailableList extends StatelessWidget {
  /// Creates the list.
  const new({
    required this.result,
    required this.hasRepos,
    required this.busy,
    required this.onInstall,
    this.hidden = 0,
    super.key,
  });

  /// Offers and per-repo errors.
  final AvailableResult result;

  /// Whether any repo is configured (for the empty message).
  final bool hasRepos;

  /// Ids with an operation in flight.
  final Set<String> busy;

  /// Installs or updates an entry.
  final void Function(PluginIndexEntry) onInstall;

  /// Offers left out of [result] by the language filter.
  final int hidden;

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return Column(
      children: [
        for (final e in result.errors.entries)
          ListTile(
            leading: Icon(Icons.error_outline, color: error),
            title: Text(
              redactUrlQueries(e.key),
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(redactUrlQueries(e.value)),
          ),
        if (result.plugins.isEmpty && result.errors.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: switch ((hasRepos, hidden)) {
              (false, _) => const EmptyMark(
                icon: Icons.link_off,
                semanticLabel: 'Add a repository URL to find plugins.',
              ),
              (true, 0) => const EmptyMark(
                icon: Icons.extension_off,
                semanticLabel: 'These repositories offer no plugins.',
              ),
              _ => EmptyMark(
                icon: Icons.translate,
                semanticLabel: hiddenByLanguageMessage(hidden),
              ),
            },
          ),
        for (final p in result.plugins)
          ListTile(
            title: Text(p.entry.manifest.name),
            subtitle: Text(
              '${p.entry.manifest.version} · ${p.entry.manifest.lang}',
            ),
            trailing: _action(p),
          ),
      ],
    );
  }

  Widget _action(AvailablePlugin p) {
    final id = p.entry.manifest.id;
    if (busy.contains(id)) {
      return const SizedBox.square(
        dimension: AppSpacing.lg,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return switch (p.availability) {
      PluginAvailability.installed => const Icon(
        Icons.check,
        semanticLabel: 'Installed',
      ),
      PluginAvailability.available => IconButton.filled(
        style: IconButton.styleFrom(minimumSize: _tap),
        onPressed: () => onInstall(p.entry),
        icon: const Icon(Icons.download, semanticLabel: 'Install'),
      ),
      PluginAvailability.updatable => IconButton.filled(
        style: IconButton.styleFrom(minimumSize: _tap),
        onPressed: () => onInstall(p.entry),
        icon: const Icon(Icons.upgrade, semanticLabel: 'Update'),
      ),
    };
  }
}

/// Installed plugins with an uninstall button; live from the manager.
class InstalledList extends StatefulWidget {
  /// Creates the list.
  const new({
    required this.manager,
    required this.busy,
    required this.onUninstall,
    super.key,
  });

  /// Provides the installed set.
  final PluginManager manager;

  /// Ids with an operation in flight.
  final Set<String> busy;

  /// Asks to remove a plugin.
  final void Function(InstalledPlugin) onUninstall;

  @override
  State<InstalledList> createState() => _InstalledListState();
}

class _InstalledListState extends State<InstalledList> {
  // Own subscription: the list may be disposed and rebuilt while scrolling.
  late final Stream<List<InstalledPlugin>> _stream = widget.manager
      .watchInstalled();

  @override
  Widget build(BuildContext context) => StreamBuilder<List<InstalledPlugin>>(
    stream: _stream,
    builder: (context, snap) {
      // Nothing yet: no "none installed" claim before the first read.
      if (!snap.hasData && !snap.hasError) return const SizedBox.shrink();
      final list = snap.data ?? const <InstalledPlugin>[];
      if (list.isEmpty) {
        return const Padding(
          padding: EdgeInsets.all(AppSpacing.md),
          child: EmptyMark(
            icon: Icons.extension_off,
            semanticLabel: 'No plugins installed.',
          ),
        );
      }
      return Column(
        children: [
          for (final p in list)
            ListTile(
              title: Text(p.manifest.name),
              subtitle: Text(
                'plugin:${p.manifest.id} · ${p.manifest.version} · '
                '${p.origin}',
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                style: IconButton.styleFrom(minimumSize: _tap),
                icon: Icon(
                  Icons.delete_outline,
                  semanticLabel: 'Uninstall ${p.manifest.name}',
                ),
                onPressed: widget.busy.contains(p.manifest.id)
                    ? null
                    : () => widget.onUninstall(p),
              ),
            ),
        ],
      );
    },
  );
}
