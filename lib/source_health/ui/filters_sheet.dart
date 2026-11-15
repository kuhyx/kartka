import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/source_health/install/keep_reconciler.dart';
import 'package:kartka/source_health/model/source_health_meta.dart';
import 'package:kartka/source_health/model/source_health_record.dart';
import 'package:kartka/source_health/ranking.dart';
import 'package:kartka/source_health/scoring/profile.dart';
import 'package:kartka/source_health/scoring/profile_store.dart';
import 'package:kartka/source_health/ui/counts_header.dart';
import 'package:kartka/source_health/ui/filter_bar.dart';
import 'package:kartka/source_health/ui/freshness_banner.dart';
import 'package:kartka/source_health/ui/keep_actions_bar.dart';
import 'package:kartka/source_health/ui/query_bar.dart';
import 'package:kartka/source_health/ui/scoring_page.dart';

/// How many facets of [q] (besides the search text) are off their default.
int activeFilterCount(HealthQuery q) => [
  q.sort != HealthSort.rank,
  q.reversed,
  q.verdicts.isNotEmpty,
  q.lang != null,
  q.origin != null,
  q.reasons.isNotEmpty,
  q.minScore > 0,
].where((on) => on).length;

/// The header's "Filters" button; a badge counts the active facets of
/// [query].
class FiltersButton extends StatelessWidget {
  /// Creates the button.
  const new({required this.query, required this.onPressed, super.key});

  /// The current query.
  final HealthQuery query;

  /// Opens the sheet.
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final active = activeFilterCount(query);
    return IconButton.filledTonal(
      key: const Key('open-filters'),
      icon: Badge(
        isLabelVisible: active > 0,
        label: Text('$active'),
        child: const Icon(Icons.tune, semanticLabel: 'Filters'),
      ),
      onPressed: onPressed,
    );
  }
}

/// Everything the Sources tab no longer fits in its header: sort and
/// filters, the freshness note, counts, Keep status, Scoring and Migrate.
/// [query] is live, so edits show in the grid behind the sheet.
class FiltersSheet extends StatelessWidget {
  /// Creates the sheet over the [records] shown when it opened.
  const new({
    required this.records,
    required this.meta,
    required this.query,
    required this.now,
    this.scoring,
    this.autoInstall,
    this.onMigrate,
    super.key,
  });

  /// Every record of the ranking.
  final List<SourceHealthRecord> records;

  /// The run summary, if published.
  final SourceHealthMeta? meta;

  /// The live query the sheet edits.
  final ValueNotifier<HealthQuery> query;

  /// Current time, for the stale check.
  final DateTime now;

  /// The scoring profile store; null hides the Scoring button.
  final ScoringProfileStore? scoring;

  /// The Keep auto-install whose status is shown.
  final KeepReconciler? autoInstall;

  /// Opens "Migrate to better sources"; null hides the button.
  final void Function(BuildContext context)? onMigrate;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: ValueListenableBuilder<HealthQuery>(
        valueListenable: query,
        builder: (context, q, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: AppSpacing.sm,
          children: [
            FreshnessBanner(at: lastEvaluated(records), now: now),
            QueryBar(
              query: q,
              langs: langsOf(records),
              origins: originsOf(records),
              onChanged: (v) => query.value = v,
            ),
            FilterBar(query: q, onChanged: (v) => query.value = v),
            if (scoring case final store?) _scoringButton(store),
            KeepActionsBar(autoInstall: autoInstall, onMigrate: onMigrate),
            CountsHeader(
              records: records,
              meta: meta,
              showing: q.apply(records).length,
            ),
          ],
        ),
      ),
    ),
  );

  Widget _scoringButton(ScoringProfileStore store) =>
      ValueListenableBuilder<ScoringProfile>(
        valueListenable: store.profile,
        builder: (context, p, _) => IconButton.outlined(
          key: const Key('open-scoring'),
          style: IconButton.styleFrom(minimumSize: const Size.square(48)),
          icon: Icon(
            p.isDefault ? Icons.tune : Icons.sync,
            semanticLabel: 'Scoring: ${p.name}',
          ),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => ScoringPage(store: store)),
          ),
        ),
      );
}
