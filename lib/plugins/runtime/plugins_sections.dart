import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/core/redact.dart';
import 'package:kartka/plugins/runtime/plugin_index.dart';
import 'package:kartka/plugins/runtime/plugin_manager.dart';
import 'package:kartka/plugins/runtime/plugin_store.dart';

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
            decoration: const InputDecoration(labelText: 'Repository URL'),
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
            tooltip: 'Add repository',
            icon: const Icon(Icons.add),
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
            child: Text(
              hasRepos
                  ? 'These repositories offer no plugins.'
                  : 'Add a repository URL to find plugins.',
            ),
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
      PluginAvailability.installed => const Icon(Icons.check),
      PluginAvailability.available => FilledButton(
        onPressed: () => onInstall(p.entry),
        child: const Text('Install'),
      ),
      PluginAvailability.updatable => FilledButton(
        onPressed: () => onInstall(p.entry),
        child: const Text('Update'),
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
          child: Text('No plugins installed.'),
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
                tooltip: 'Uninstall ${p.manifest.name}',
                icon: const Icon(Icons.delete_outline),
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
