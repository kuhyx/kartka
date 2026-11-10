import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/source_health/cut_reasons.dart';
import 'package:kartka/source_health/model/source_health_record.dart';
import 'package:kartka/source_health/scoring/profile.dart';
import 'package:kartka/source_health/ui/health_badge.dart';
import 'package:kartka/source_health/ui/health_icons.dart';

/// A record's cut reasons as glyphs: a heading glyph, then one glyph per
/// reason code, in danger (why the score is low) or warning (kept on score
/// despite them) colour. The sentences ([explainCutReasons]) and the heading
/// are spoken only; the numbers behind them are on the metrics.
class ReasonMarks extends StatelessWidget {
  /// Marks for [record]; [nameOf] names a subset's covering source.
  const new(
    this.record, {
    this.nameOf,
    this.keepScore = kDefaultKeepScore,
    super.key,
  });

  /// The source.
  final SourceHealthRecord record;

  /// Names other sources, for the spoken subset reason.
  final SourceNameOf? nameOf;

  /// The active profile's keep bar, for the spoken "kept despite" heading.
  final double keepScore;

  @override
  Widget build(BuildContext context) {
    final r = record;
    if (r.cutReasons.isEmpty) return const SizedBox.shrink();
    final warn = keptDespiteReasons(r);
    final s = statusColors(context);
    final color = warn ? s.warning : s.danger;
    final sentences = explainCutReasons(r, nameOf: nameOf);
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Icon(
          warn ? Icons.warning_amber_rounded : Icons.trending_down,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          semanticLabel: warn ? keptDespiteHeading(keepScore) : lowScoreHeading,
        ),
        for (final (i, code) in r.cutReasons.indexed)
          Icon(cutCodeIcon(code), color: color, semanticLabel: sentences[i]),
      ],
    );
  }
}
