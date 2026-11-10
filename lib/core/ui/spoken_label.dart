import 'package:flutter/material.dart';

/// Wraps [child] in a semantics node that only screen readers speak.
///
/// The textgate rule bans painted words; the old wording survives here as a
/// spoken label so tests and accessibility keep a name for the control. The
/// parameter is named `semanticLabel` on purpose: nothing paints it.
class SpokenLabel extends StatelessWidget {
  /// Speaks [semanticLabel] for [child], in a node of its own.
  const new({required this.semanticLabel, required this.child, super.key});

  /// What a screen reader says; never painted.
  final String semanticLabel;

  /// The painted, word-free widget.
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Semantics(label: semanticLabel, container: true, child: child);
}

/// A large faded glyph for an empty or failed state, spoken as [semanticLabel].
///
/// Replaces design_system's worded `EmptyState` (title + message).
class EmptyMark extends StatelessWidget {
  /// Draw [icon] faded in the middle of the space.
  const new({required this.icon, required this.semanticLabel, super.key});

  /// The glyph that names the state.
  final IconData icon;

  /// The old title and message, for screen readers only.
  final String semanticLabel;

  @override
  Widget build(BuildContext context) => Center(
    child: Icon(
      icon,
      size: 64,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      semanticLabel: semanticLabel,
    ),
  );
}
