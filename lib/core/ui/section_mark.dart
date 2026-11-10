import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// Word-free stand-in for design_system's `SectionHeader`: a glyph in the
/// section-header slot, its old title kept as [semanticLabel] only.
class SectionMark extends StatelessWidget {
  /// Heads a section with [icon], padded for an unpadded `ListView`.
  const new(this.icon, {required this.semanticLabel, super.key});

  /// The glyph that names the section.
  final IconData icon;

  /// The old section title, for screen readers only.
  final String semanticLabel;

  @override
  Widget build(BuildContext context) => Padding(
    padding: SectionHeader.defaultPadding,
    child: Align(
      alignment: Alignment.centerLeft,
      child: Icon(
        icon,
        color: Theme.of(context).colorScheme.primary,
        semanticLabel: semanticLabel,
      ),
    ),
  );
}
