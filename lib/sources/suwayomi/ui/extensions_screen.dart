import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:kartka/core/redact.dart';
import 'package:kartka/core/ui/confirm_mark.dart';
import 'package:kartka/core/ui/section_mark.dart';
import 'package:kartka/core/ui/snack_mark.dart';
import 'package:kartka/core/ui/spoken_label.dart';
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
        !await confirmMark(
          context,
          icon: Icons.extension_off,
          semanticLabel: 'Uninstall ${e.name}? Its sources leave Browse.',
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
      final (icon, verb) = switch (action) {
        ExtensionAction.install => (Icons.download_done, 'Installed'),
        ExtensionAction.update => (Icons.published_with_changes, 'Updated'),
        ExtensionAction.uninstall => (Icons.delete_forever, 'Uninstalled'),
      };
      showMark(
        context,
        SpokenLabel(
          semanticLabel: '$verb ${e.name}',
          child: ExcludeSemantics(
            child: Row(
              children: [
                Icon(icon),
                const SizedBox(width: AppSpacing.sm),
                Flexible(child: Text(e.name)),
              ],
            ),
          ),
        ),
      );
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
      if (installed.isNotEmpty)
        const SectionMark(
          Icons.check_circle_outline,
          semanticLabel: 'Installed',
        ),
      ...installed.map(tile),
      if (available.isNotEmpty)
        const SectionMark(
          Icons.cloud_download_outlined,
          semanticLabel: 'Available',
        ),
      ...available.map(tile),
    ];
  }

  Widget _body() {
    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          const EmptyMark(
            icon: Icons.cloud_off,
            semanticLabel: "Can't list extensions",
          ),
          // The server's own error is content: it stays readable.
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Text(_error!, textAlign: TextAlign.center),
          ),
          Center(
            child: IconButton.filled(
              style: IconButton.styleFrom(minimumSize: const Size.square(48)),
              onPressed: _load,
              icon: const Icon(Icons.refresh, semanticLabel: 'Retry'),
            ),
          ),
        ],
      );
    }
    final items = _items;
    if (items == null) return const Center(child: CircularProgressIndicator());
    if (items.isEmpty) {
      return const EmptyMark(
        icon: Icons.extension_off,
        semanticLabel:
            'No extensions. The server has no extension store; add one '
            "(e.g. Keiyoushi) in the server's settings, then come back.",
      );
    }
    final rows = _rows(items);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(
                Icons.search,
                semanticLabel: 'Filter by name or language',
              ),
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
        appBar: AppBar(
          title: const Icon(Icons.extension, semanticLabel: 'Extensions'),
        ),
        body: _body(),
      ),
    ),
  );
}
