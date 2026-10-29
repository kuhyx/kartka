import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:kartka/core/redact.dart';
import 'package:kartka/sources/suwayomi/suwayomi_exceptions.dart';
import 'package:kartka/sources/suwayomi/suwayomi_extensions.dart';
import 'package:kartka/sources/suwayomi/ui/extension_tile.dart';

/// Installed and available Suwayomi extensions, with install, update and
/// uninstall. What is "available" is whatever the server's stores offer.
class ExtensionsScreen extends StatefulWidget {
  /// Creates the screen.
  const new({required this.api, this.diagnostics, super.key});

  /// The server's extension API.
  final SuwayomiExtensionsApi api;

  /// Where a failed listing (the Retry screen) is logged.
  final DiagnosticsLog? diagnostics;

  @override
  State<ExtensionsScreen> createState() => _ExtensionsState();
}

class _ExtensionsState extends State<ExtensionsScreen> {
  List<SuwayomiExtension>? _items;
  String? _error;
  String _filter = '';
  final _busy = <String>{};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _error = _items = null);
    try {
      final items = await widget.api.list();
      if (mounted) setState(() => _items = items);
    } on Object catch (e, stack) {
      final log = widget.diagnostics;
      if (log != null) {
        ErrorReporter.of(log).report('suwayomi.extensions', e, stack: stack);
      }
      if (mounted) setState(() => _error = _describe(e));
    }
  }

  static String _describe(Object e) =>
      redactUrlQueries(e is SuwayomiException ? e.message : '$e');

  Future<void> _run(SuwayomiExtension e, ExtensionAction action) async {
    if (action == ExtensionAction.uninstall &&
        !await confirmDestructive(
          context,
          title: 'Uninstall ${e.name}?',
          message: 'Its sources disappear from Browse until reinstalled.',
          confirmLabel: 'Uninstall',
        )) {
      return;
    }
    setState(() => _busy.add(e.pkgName));
    try {
      final api = widget.api;
      final updated = await switch (action) {
        ExtensionAction.install => api.install(e.pkgName),
        ExtensionAction.update => api.update(e.pkgName),
        ExtensionAction.uninstall => api.uninstall(e.pkgName),
      };
      if (!mounted) return;
      setState(() {
        _items = sortExtensions([
          for (final x in _items!)
            if (x.pkgName == e.pkgName) updated else x,
        ]);
      });
      final verb = switch (action) {
        ExtensionAction.install => 'Installed',
        ExtensionAction.update => 'Updated',
        ExtensionAction.uninstall => 'Uninstalled',
      };
      showToast(context, '$verb ${e.name}');
    } on Object catch (err) {
      if (mounted) showError(context, '${e.name}: ${_describe(err)}');
    } finally {
      if (mounted) setState(() => _busy.remove(e.pkgName));
    }
  }

  bool _matches(SuwayomiExtension e) {
    final q = _filter.trim().toLowerCase();
    return q.isEmpty ||
        e.name.toLowerCase().contains(q) ||
        e.lang.toLowerCase() == q;
  }

  List<Widget> _rows(List<SuwayomiExtension> items) {
    final shown = items.where(_matches);
    final installed = shown.where((e) => e.isInstalled).toList();
    final available = shown.where((e) => !e.isInstalled).toList();
    Widget tile(SuwayomiExtension e) => ExtensionTile(
      key: ValueKey(e.pkgName),
      extension: e,
      busy: _busy.contains(e.pkgName),
      onAction: (a) => _run(e, a),
    );
    return [
      if (installed.isNotEmpty) const SectionHeader('Installed'),
      ...installed.map(tile),
      if (available.isNotEmpty) const SectionHeader('Available'),
      ...available.map(tile),
    ];
  }

  Widget _body() {
    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          EmptyState(
            icon: Icons.cloud_off,
            title: "Can't list extensions",
            message: _error!,
          ),
          Center(
            child: FilledButton(onPressed: _load, child: const Text('Retry')),
          ),
        ],
      );
    }
    final items = _items;
    if (items == null) return const Center(child: CircularProgressIndicator());
    if (items.isEmpty) {
      return const EmptyState(
        icon: Icons.extension_off,
        title: 'No extensions',
        message:
            'The server has no extension store. Add one (e.g. Keiyoushi) '
            "in the server's settings, then come back.",
      );
    }
    final rows = _rows(items);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: TextField(
            decoration: const InputDecoration(
              labelText: 'Filter by name or language',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => _filter = v),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: rows.length,
            itemBuilder: (_, i) => rows[i],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.escape): () =>
          Navigator.maybePop(context),
    },
    child: Focus(
      autofocus: true,
      child: Scaffold(
        appBar: AppBar(title: const Text('Extensions')),
        body: _body(),
      ),
    ),
  );
}
