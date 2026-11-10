import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/reader/data/reader_prefs.dart';
import 'package:kartka/reader/data/reader_settings.dart';
import 'package:kartka/reader/ui/reader_settings_panel.dart';

/// The reader's entry in the app settings screen.
class ReaderSettingsTile extends StatefulWidget {
  /// A tile editing the settings in [prefs].
  const new({required this.prefs, super.key});

  /// Where reader settings are stored.
  final ReaderPrefs prefs;

  @override
  State<ReaderSettingsTile> createState() => _ReaderSettingsTileState();
}

class _ReaderSettingsTileState extends State<ReaderSettingsTile> {
  ReaderSettings? _settings;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final s = await widget.prefs.settings();
    if (mounted) setState(() => _settings = s);
  }

  Future<void> _save(ReaderSettings s) async {
    setState(() => _settings = s);
    await widget.prefs.saveSettings(s);
  }

  Future<void> _edit() => showModalBottomSheet<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setSheet) => ReaderSettingsPanel(
        settings: _settings ?? const ReaderSettings(),
        onChanged: (s) {
          setSheet(() {});
          unawaited(_save(s));
        },
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final s = _settings;
    return ListTile(
      leading: const Icon(
        Icons.chrome_reader_mode_outlined,
        semanticLabel: 'Reader',
      ),
      title: s == null
          ? null
          : Row(
              spacing: AppSpacing.sm,
              children: [
                Icon(s.defaultMode.icon, semanticLabel: s.defaultMode.label),
                const Icon(
                  Icons.downloading,
                  semanticLabel: 'pages prefetched',
                ),
                Text('${s.prefetchAhead}'),
              ],
            ),
      onTap: s == null ? null : () => unawaited(_edit()),
    );
  }
}
