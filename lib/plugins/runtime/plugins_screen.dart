import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/core/redact.dart';
import 'package:kartka/core/ui/confirm_mark.dart';
import 'package:kartka/core/ui/section_mark.dart';
import 'package:kartka/plugins/runtime/plugin_languages.dart';
import 'package:kartka/plugins/runtime/plugin_manager.dart';
import 'package:kartka/plugins/runtime/plugin_store.dart';
import 'package:kartka/plugins/runtime/plugins_sections.dart';

const _tap = Size.square(48);

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
  List<String> _langs = kDefaultPluginLanguages;
  bool _loading = true;
  // Until the first load lands, the empty states would be false claims.
  bool _loaded = false;
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
    final langs = await _m.store.languages();
    if (!mounted) return;
    setState(() {
      _repos = repos;
      _langs = langs ?? kDefaultPluginLanguages;
      _available = available;
      _loading = false;
      _loaded = true;
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

  void _setLanguages(List<String> langs) {
    setState(() => _langs = langs);
    unawaited(_m.store.setLanguages(langs));
  }

  Future<void> _uninstall(InstalledPlugin p) async {
    final ok = await confirmMark(
      context,
      icon: Icons.extension_off,
      semanticLabel: 'Uninstall ${p.manifest.name}?',
      confirmLabel: 'Uninstall',
    );
    if (ok) await _guarded(p.manifest.id, () => _m.uninstall(p.manifest.id));
  }

  @override
  Widget build(BuildContext context) {
    final shown = shownPlugins(_available.plugins, _langs);
    return Scaffold(
      appBar: AppBar(
        title: const Icon(Icons.extension_outlined, semanticLabel: 'Plugins'),
        actions: [
          IconButton(
            style: IconButton.styleFrom(minimumSize: _tap),
            icon: const Icon(Icons.refresh, semanticLabel: 'Refresh'),
            onPressed: _loading ? null : _refresh,
          ),
        ],
      ),
      body: ListView(
        children: [
          const SectionMark(Icons.link, semanticLabel: 'Repositories'),
          AddRepoRow(
            controller: _url,
            busy: _busy.contains('repo'),
            onAdd: _addRepo,
          ),
          for (final r in _repos)
            ListTile(
              title: Text(r, overflow: TextOverflow.ellipsis),
              trailing: IconButton(
                style: IconButton.styleFrom(minimumSize: _tap),
                icon: const Icon(
                  Icons.delete_outline,
                  semanticLabel: 'Remove repository',
                ),
                onPressed: () => _guarded('repo', () => _m.removeRepo(r)),
              ),
            ),
          const SectionMark(
            Icons.cloud_download_outlined,
            semanticLabel: 'Available',
          ),
          if (_available.plugins.isNotEmpty)
            PluginLanguagesChip(
              selected: _langs,
              counts: pluginLanguageCounts(_available.plugins),
              onChanged: _setLanguages,
            ),
          // Before the first load the bar is the whole loading state.
          if (_loading)
            const LinearProgressIndicator(semanticsLabel: 'Loading plugins…'),
          if (_loaded)
            AvailableList(
              result: AvailableResult(shown, _available.errors),
              hidden: _available.plugins.length - shown.length,
              hasRepos: _repos.isNotEmpty,
              busy: _busy,
              onInstall: (e) => _guarded(e.manifest.id, () => _m.install(e)),
            ),
          const SectionMark(
            Icons.check_circle_outline,
            semanticLabel: 'Installed',
          ),
          if (_loaded)
            InstalledList(manager: _m, busy: _busy, onUninstall: _uninstall),
        ],
      ),
    );
  }
}
