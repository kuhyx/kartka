import 'package:material_ui/material_ui.dart';

/// Word-free stand-in for design_system's `confirmDestructive`.
///
/// The dialog shows [icon] in the error colour; the old question survives as
/// [semanticLabel] for screen readers and tests. Returns true only when the
/// user taps the confirm button ([confirmIcon], spoken as [confirmLabel]).
/// A non-zero [count] (e.g. library titles affected) badges the icon.
Future<bool> confirmMark(
  BuildContext context, {
  required IconData icon,
  required String semanticLabel,
  IconData confirmIcon = Icons.delete_outline,
  String confirmLabel = 'Delete',
  int count = 0,
}) async {
  final error = Theme.of(context).colorScheme.error;
  const size = Size.square(48);
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Center(
        child: Badge.count(
          count: count,
          isLabelVisible: count > 0,
          child: Icon(
            icon,
            size: 48,
            color: error,
            semanticLabel: semanticLabel,
          ),
        ),
      ),
      actions: [
        IconButton(
          style: IconButton.styleFrom(minimumSize: size),
          icon: const Icon(Icons.close, semanticLabel: 'Cancel'),
          tooltip: 'Cancel',
          onPressed: () => Navigator.of(dialog).pop(false),
        ),
        IconButton.filled(
          style: IconButton.styleFrom(
            minimumSize: size,
            backgroundColor: error,
          ),
          icon: Icon(confirmIcon, semanticLabel: confirmLabel),
          tooltip: 'Confirm',
          onPressed: () => Navigator.of(dialog).pop(true),
        ),
      ],
    ),
  );
  return ok ?? false;
}
