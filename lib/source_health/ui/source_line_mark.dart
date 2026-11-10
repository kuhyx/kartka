import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/core/ui/spoken_label.dart';
import 'package:kartka/source_health/labels.dart';
import 'package:kartka/source_health/model/source_health_record.dart';
import 'package:kartka/source_health/ui/health_icons.dart';

/// [sourceLine] without words: the origin glyph, then the language code,
/// the tested-language scope (`EN+JA`, or a globe for all languages) and,
/// with [withId], the source id. Spoken as [sourceLine].
class SourceLineMark extends StatelessWidget {
  /// Marks for [record].
  const new(this.record, {this.withId = false, super.key});

  /// The source.
  final SourceHealthRecord record;

  /// Adds the source id.
  final bool withId;

  @override
  Widget build(BuildContext context) {
    final r = record;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final style = TextStyle(color: muted, fontSize: AppTextSize.label);
    final scope = r.langScope;
    final codes = [
      r.lang,
      if (scope != null && scope != 'unrestricted') scope.toUpperCase(),
      if (withId) r.id,
    ].where((s) => s.isNotEmpty).join(' · ');
    return SpokenLabel(
      semanticLabel: sourceLine(r, withId: withId),
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: AppSpacing.xs,
          children: [
            Icon(originIcon(r.origin), size: AppTextSize.body, color: muted),
            if (scope == 'unrestricted')
              Icon(Icons.public, size: AppTextSize.body, color: muted),
            Flexible(child: Text(codes, style: style)),
          ],
        ),
      ),
    );
  }
}

/// The DEFAULT-profile score next to a custom one ([defaultScoreNote]): a
/// restore glyph and the number; nothing when the note is null.
class DefaultScoreMark extends StatelessWidget {
  /// Marks for [record].
  const new(this.record, {super.key});

  /// The source.
  final SourceHealthRecord record;

  @override
  Widget build(BuildContext context) {
    final note = defaultScoreNote(record);
    if (note == null) return const SizedBox.shrink();
    return IconValue(
      Icons.settings_backup_restore,
      note.split(' ').last,
      semanticLabel: note,
      key: const Key('default-score'),
    );
  }
}
