import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kartka/source_health/cut_reasons.dart';
import 'package:kartka/source_health/metric_explanations.dart';
import 'package:kartka/source_health/metric_text.dart';
import 'package:kartka/source_health/model/source_health_record.dart';
import 'package:kartka/source_health/score_breakdown.dart';
import 'package:kartka/source_health/ui/freshness_banner.dart';
import 'package:kartka/source_health/ui/health_badge.dart';
import 'package:kartka/source_health/ui/metric_tile.dart';
import 'package:kartka/source_health/ui/query_bar.dart';

/// One source's evaluation: verdict, cut reasons, every metric with what it
/// means and its threshold, and the score breakdown. Escape goes back.
class SourceDetailPage extends StatelessWidget {
  /// Creates the page for [record]; [all] resolves the subset-of link.
  const new({
    required this.record,
    required this.all,
    required this.now,
    super.key,
  });

  /// The source shown.
  final SourceHealthRecord record;

  /// Every record of the ranking.
  final List<SourceHealthRecord> all;

  /// Current time, for the stale check.
  final DateTime now;

  SourceHealthRecord? _find(String id) =>
      all.where((r) => r.id == id).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final r = record;
    final muted = TextStyle(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
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
                  Text(
                    'Evaluator score ${scoreText(r.score)} · '
                    '${r.rank == null ? 'unranked' : 'rank #${r.rank}'}',
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                [
                  originLabel(r.origin),
                  r.lang,
                  r.id,
                ].where((s) => s.isNotEmpty).join(' · '),
                style: muted,
              ),
              const SizedBox(height: AppSpacing.sm),
              FreshnessBanner(at: r.probedAt, now: now),
              if (r.needsBrowserEngine) ...[
                const Align(
                  alignment: Alignment.centerLeft,
                  child: BrowserEngineChip(),
                ),
                const SizedBox(height: AppSpacing.xs),
                const Text(
                  'Its extension needs a browser engine Kartka does not ship, '
                  'so some requests fail; flagged, not cut.',
                ),
              ],
              if (r.cutReasons.isNotEmpty) ...[
                const SectionHeader('Why it was cut'),
                for (final why in explainCutReasons(
                  r,
                  nameOf: (id) => _find(id)?.name,
                ))
                  Text(why),
              ],
              if (subset != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.call_split),
                    label: Text('Open ${subset.name}'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => SourceDetailPage(
                          record: subset,
                          all: all,
                          now: now,
                        ),
                      ),
                    ),
                  ),
                ),
              const SectionHeader('Metrics'),
              for (final e in explainMetrics(r)) MetricTile(e),
              const SectionHeader('Score breakdown'),
              ScoreTable(scoreBreakdown(r)),
            ],
          ),
        ),
      ),
    );
  }
}
