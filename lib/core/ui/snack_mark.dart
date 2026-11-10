import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// Word-free stand-in for design_system's `showToast` / `showError`: shows
/// [mark] (icons and numbers, its words in a semantic label) in a snack bar.
///
/// [error] paints it in the danger hue, the same second channel `showError`
/// uses. Replaces any snack bar already showing; a no-op without a
/// `ScaffoldMessenger` (an async callback after its screen was popped).
void showMark(BuildContext context, Widget mark, {bool error = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final colors = context.statusColors;
  final fg = error
      ? colors.onStatus
      : Theme.of(context).colorScheme.onInverseSurface;
  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        backgroundColor: error ? colors.danger : null,
        duration: Duration(seconds: error ? 6 : 3),
        content: IconTheme.merge(
          data: IconThemeData(color: fg),
          child: DefaultTextStyle.merge(
            style: TextStyle(color: fg),
            child: mark,
          ),
        ),
      ),
    );
}
