import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/reader/data/reader_settings.dart';
import 'package:kartka/reader/logic/reader_mode.dart';
import 'package:kartka/reader/logic/tap_zones.dart';

/// Editor for the global reader settings, used in the reader's sheet and
/// in the app's settings screen.
class ReaderSettingsPanel extends StatelessWidget {
  /// Edits [settings], reporting every change to [onChanged].
  const new({required this.settings, required this.onChanged, super.key});

  /// Current values.
  final ReaderSettings settings;

  /// Receives the edited settings.
  final ValueChanged<ReaderSettings> onChanged;

  @override
  Widget build(BuildContext context) => ListView(
    shrinkWrap: true,
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
    children: [
      ListTile(
        title: const Text('Default reading mode'),
        trailing: DropdownButton<ReaderMode>(
          value: settings.defaultMode,
          onChanged: (m) => onChanged(settings.copyWith(defaultMode: m)),
          items: [
            for (final m in ReaderMode.values)
              DropdownMenuItem(value: m, child: Text(m.label)),
          ],
        ),
      ),
      ListTile(
        title: const Text('Tap zones'),
        trailing: DropdownButton<TapZoneLayout>(
          value: settings.tapLayout,
          onChanged: (l) => onChanged(settings.copyWith(tapLayout: l)),
          items: [
            for (final l in TapZoneLayout.values)
              DropdownMenuItem(value: l, child: Text(l.label)),
          ],
        ),
      ),
      SwitchListTile(
        title: const Text('Invert tap zones'),
        value: settings.invertTaps,
        onChanged: (v) => onChanged(settings.copyWith(invertTaps: v)),
      ),
      ListTile(
        title: Text('Prefetch ${settings.prefetchAhead} pages ahead'),
        subtitle: Slider(
          value: settings.prefetchAhead.toDouble(),
          max: ReaderSettings.maxPrefetch.toDouble(),
          divisions: ReaderSettings.maxPrefetch,
          label: '${settings.prefetchAhead}',
          onChanged: (v) =>
              onChanged(settings.copyWith(prefetchAhead: v.round())),
        ),
      ),
    ],
  );
}
