import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/core/redact.dart';
import 'package:kartka/plugins/runtime/plugin_manager.dart';
import 'package:kartka/plugins/runtime/plugin_store.dart';
import 'package:kartka/plugins/runtime/plugins_sections.dart';

/// More > Plugins: repos, what they offer, and what is installed.
class PluginsScreen extends StatefulWidget {
  /// Creates the screen over [manager].
  const new({required this.manager, super.key});

  /// Source of truth for repos and installs.
  final PluginManager manager;

  @override
  State<PluginsScreen> createState() => _PluginsScreenState();
}

class _PluginsScreenState extends State<PluginsScreen> {
  final _url = TextEditingController();
  List<String> _repos = [];
  AvailableResult _available = const AvailableResult([], {});
  bool _loading = true;
  final Set<String> _busy = {};

  PluginManager get _m => widget.manager;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final repos = await _m.repos();
    final available = await _m.available();
    if (!mounted) return;
    setState(() {
      _repos = repos;
      _available = available;
      _loading = false;
    });
  }

  /// Runs [action], shows its error (which names the plugin) as a toast.
  Future<void> _guarded(String key, Future<void> Function() action) async {
    setState(() => _busy.add(key));
    try {
      await action();
    } on Object catch (e) {
      if (mounted) showError(context, redactUrlQueries('$e'));
    }
    if (mounted) setState(_busy.clear);
    await _refresh();
  }

  Future<void> _addRepo() async {
    final url = _url.text;
    await _guarded('repo', () => _m.addRepo(url));
    if (mounted && _repos.contains(url.trim())) _url.clear();
  }

  Future<void> _uninstall(InstalledPlugin p) async {
    final ok = await confirmDestructive(
      context,
      title: 'Uninstall ${p.manifest.name}?',
      message: 'Its settings are removed too.',
      confirmLabel: 'Uninstall',
    );
    if (ok) await _guarded(p.manifest.id, () => _m.uninstall(p.manifest.id));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Plugins'),
      actions: [
        IconButton(
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh),
          onPressed: _loading ? null : _refresh,
        ),
      ],
    ),
    body: ListView(
      children: [
        const SectionHeader(
          'Repositories',
          padding: SectionHeader.defaultPadding,
        ),
        AddRepoRow(
          controller: _url,
          busy: _busy.contains('repo'),
          onAdd: _addRepo,
        ),
        for (final r in _repos)
          ListTile(
            title: Text(r, overflow: TextOverflow.ellipsis),
            trailing: IconButton(
              tooltip: 'Remove repository',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _guarded('repo', () => _m.removeRepo(r)),
            ),
          ),
        const SectionHeader('Available', padding: SectionHeader.defaultPadding),
        if (_loading) const LinearProgressIndicator(),
        AvailableList(
          result: _available,
          hasRepos: _repos.isNotEmpty,
          busy: _busy,
          onInstall: (e) => _guarded(e.manifest.id, () => _m.install(e)),
        ),
        const SectionHeader('Installed', padding: SectionHeader.defaultPadding),
        InstalledList(manager: _m, busy: _busy, onUninstall: _uninstall),
      ],
    ),
  );
}
