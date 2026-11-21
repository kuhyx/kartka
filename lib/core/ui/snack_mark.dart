import 'package:design_system/design_system.dart';
import 'package:material_ui/material_ui.dart';

/// The themed wrapper that [showMark] passes into its snackbar.
///
/// Exposed as its own widget so callers can pattern-match on it in code
/// (e.g. error report text extraction) instead of walking through an opaque
/// pair of `merge` Builders.
class SnackMark extends StatelessWidget {
  /// The raw mark widget (icon, number, etc.).
  const new({required this.mark, required this.fg, super.key});

  /// The glyph/number shown.
  final Widget mark;

  /// The foreground colour the theme applied.
  final Color fg;

  @override
  Widget build(BuildContext context) => IconTheme.merge(
    data: IconThemeData(color: fg),
    child: DefaultTextStyle.merge(
      style: TextStyle(color: fg),
      child: mark,
    ),
  );
}

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
        content: SnackMark(mark: mark, fg: fg),
      ),
    );
}
