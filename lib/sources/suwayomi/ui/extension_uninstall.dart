import 'package:kartka/core/ui/confirm_mark.dart';
import 'package:kartka/sources/suwayomi/suwayomi_extensions.dart';
import 'package:material_ui/material_ui.dart';

/// Extensions the bulk uninstall keeps unless unticked: kuhy's two
/// favourites, matched by name or package so a renamed store entry still
/// matches. One-off: nothing about the sheet is stored.
const _keptByDefault = ['mangafire', 'atsumaru'];

bool _keptFirst(SuwayomiExtension e) => _keptByDefault.any(
  (k) => e.name.toLowerCase().contains(k) || e.pkgName.endsWith('.$k'),
);

/// How many library titles ([titleSourceIds], one source id per title) read
/// from a source of [extensions].
int libraryTitlesOf(
  Iterable<SuwayomiExtension> extensions,
  List<String> titleSourceIds,
) {
  final ids = {for (final e in extensions) ...e.sourceIds};
  return titleSourceIds.where(ids.contains).length;
}

/// Asks before uninstalling [extensions]; the badge counts the library
/// titles left without their source (their entries stay, marked missing).
Future<bool> confirmUninstall(
  BuildContext context,
  List<SuwayomiExtension> extensions,
  int titles,
) => confirmMark(
  context,
  icon: Icons.extension_off,
  semanticLabel:
      'Uninstall ${extensions.map((e) => e.name).join(', ')}? Its sources '
      'leave Browse; $titles library titles keep their entries.',
  confirmLabel: 'Uninstall',
  count: titles,
);

/// The bulk uninstall's keep-list: a sheet of the [installed] extensions,
/// MangaFire and Atsumaru ticked. Returns the unticked ones to uninstall,
/// or null when dismissed.
Future<List<SuwayomiExtension>?> pickUninstalls(
  BuildContext context,
  List<SuwayomiExtension> installed,
) => showModalBottomSheet<List<SuwayomiExtension>>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _KeepSheet(installed),
);

class _KeepSheet extends StatefulWidget {
  const new(this.installed);

  final List<SuwayomiExtension> installed;

  @override
  State<_KeepSheet> createState() => _KeepSheetState();
}

class _KeepSheetState extends State<_KeepSheet> {
  late final Set<String> _keep = {
    for (final e in widget.installed)
      if (_keptFirst(e)) e.pkgName,
  };

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final e in widget.installed)
                CheckboxListTile(
                  value: _keep.contains(e.pkgName),
                  title: Text(e.name),
                  onChanged: (v) => setState(
                    () => v! ? _keep.add(e.pkgName) : _keep.remove(e.pkgName),
                  ),
                ),
            ],
          ),
        ),
        IconButton.filled(
          style: IconButton.styleFrom(
            minimumSize: const Size.square(48),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: () => Navigator.of(context).pop([
            for (final e in widget.installed)
              if (!_keep.contains(e.pkgName)) e,
          ]),
          icon: const Icon(
            Icons.delete_sweep,
            semanticLabel: 'Uninstall the unticked',
          ),
        ),
      ],
    ),
  );
}
