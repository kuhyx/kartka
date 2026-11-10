import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kartka/core/ui/section_mark.dart';
import 'package:kartka/source_health/install/source_action_button.dart';
import 'package:kartka/source_health/install/source_installs.dart';
import 'package:kartka/source_health/labels.dart';
import 'package:kartka/source_health/metric_explanations.dart';
import 'package:kartka/source_health/metric_text.dart';
import 'package:kartka/source_health/model/source_health_record.dart';
import 'package:kartka/source_health/score_breakdown.dart';
import 'package:kartka/source_health/scoring/profile.dart';
import 'package:kartka/source_health/ui/freshness_banner.dart';
import 'package:kartka/source_health/ui/health_badge.dart';
import 'package:kartka/source_health/ui/health_icons.dart';
import 'package:kartka/source_health/ui/metric_tile.dart';
import 'package:kartka/source_health/ui/reason_marks.dart';
import 'package:kartka/source_health/ui/source_line_mark.dart';

/// One source's evaluation: verdict, cut reasons, every metric with what it
/// means and its threshold, and the score breakdown. Escape goes back.
class SourceDetailPage extends StatelessWidget {
  /// Creates the page for [record]; [all] resolves the subset-of link.
  const new({
    required this.record,
    required this.all,
    required this.now,
    this.profile = defaultScoringProfile,
    this.installs,
    super.key,
  });

  /// Install / Open state; null shows no action button.
  final SourceInstalls? installs;

  /// The active scoring profile (weights, keep bar) the page explains.
  final ScoringProfile profile;

  /// The source shown.
  final SourceHealthRecord record;

  /// Every record of the ranking.
  final List<SourceHealthRecord> all;

  /// Current time, for the stale check.
  final DateTime now;

  String _scoreLine() {
    final label = profile.isDefault
        ? 'Evaluator score'
        : 'Score (custom profile)';
    final rank = record.rank == null ? 'unranked' : 'rank #${record.rank}';
    final note = defaultScoreNote(record);
    return '$label ${scoreText(record.score)} · $rank'
        '${note == null ? '' : ' · $note'}';
  }

  SourceHealthRecord? _find(String id) =>
      all.where((r) => r.id == id).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final r = record;
    final subset = r.subsetOf == null ? null : _find(r.subsetOf!.sourceId);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.maybePop(context),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(title: Text(r.name)),
          body: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              Wrap(
                spacing: AppSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  HealthBadge(verdict: r.verdict, rank: r.rank),
                  IconValue(
                    profile.isDefault ? Icons.insights_outlined : Icons.tune,
                    scoreText(record.score),
                    semanticLabel: _scoreLine(),
                    key: const Key('score-line'),
                  ),
                  DefaultScoreMark(r),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: SourceLineMark(r, withId: true),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (installs case final i?) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: SourceActionButton(record: r, installs: i),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              FreshnessBanner(at: r.probedAt, now: now),
              if (r.needsBrowserEngine || r.reprobedOnly)
                Wrap(
                  spacing: AppSpacing.sm,
                  children: [
                    if (r.needsBrowserEngine) const BrowserEngineChip(),
                    if (r.reprobedOnly) const ReprobeChip(),
                  ],
                ),
              if (r.cutReasons.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: ReasonMarks(
                    r,
                    nameOf: (id) => _find(id)?.name,
                    keepScore: profile.keepScore,
                  ),
                ),
              if (subset != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.call_split),
                    label: Text(
                      subset.name,
                      semanticsLabel: 'Open ${subset.name}',
                    ),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => SourceDetailPage(
                          record: subset,
                          all: all,
                          now: now,
                          profile: profile,
                          installs: installs,
                        ),
                      ),
                    ),
                  ),
                ),
              const SectionMark(
                Icons.analytics_outlined,
                semanticLabel: 'Metrics',
              ),
              for (final e in explainMetrics(r, profile: profile))
                MetricTile(e),
              const SectionMark(
                Icons.functions,
                semanticLabel: 'Score breakdown',
              ),
              ScoreTable(
                scoreBreakdown(r, profile),
                pagesLoad: r.pagesLoad,
                profile: profile,
                rankedLowBecause: rankTierReasons(r),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
