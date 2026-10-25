import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/core/redact.dart';
import 'package:kartka/source_health/feed/source_health_feed.dart';
import 'package:kartka/source_health/model/source_health_meta.dart';
import 'package:kartka/source_health/model/source_health_record.dart';
import 'package:kartka/source_health/ranking.dart';
import 'package:kartka/source_health/scoring/profile.dart';
import 'package:kartka/source_health/scoring/profile_store.dart';
import 'package:kartka/source_health/ui/counts_header.dart';
import 'package:kartka/source_health/ui/filter_bar.dart';
import 'package:kartka/source_health/ui/freshness_banner.dart';
import 'package:kartka/source_health/ui/query_bar.dart';
import 'package:kartka/source_health/ui/scoring_page.dart';
import 'package:kartka/source_health/ui/source_card.dart';
import 'package:kartka/source_health/ui/source_detail_page.dart';

/// The Sources tab: the evaluator's ranking with every metric, searchable,
/// sortable and filterable, live from [feed].
class SourcesTab extends StatefulWidget {
  /// Creates the tab; [clock] is injectable for the stale check.
  const new({
    required this.feed,
    this.scoring,
    this.clock = DateTime.now,
    super.key,
  });

  /// Source of the ranking (already scored with the active profile).
  final SourceHealthFeed feed;

  /// The active scoring profile; when set, a Scoring button opens its page.
  final ScoringProfileStore? scoring;

  /// Current time.
  final DateTime Function() clock;

  @override
  State<SourcesTab> createState() => _SourcesTabState();
}

class _SourcesTabState extends State<SourcesTab> {
  late final Stream<List<SourceHealthRecord>> _records = widget.feed.watch();
  late final Stream<SourceHealthMeta?> _meta = widget.feed.watchMeta();
  // Owned here, not by the field: the query must survive the field being
  // rebuilt (and the text must stay in step with it).
  final _search = TextEditingController();
  HealthQuery _query = const HealthQuery();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  ScoringProfile get _profile =>
      widget.scoring?.profile.value ?? defaultScoringProfile;

  void _setSearch(String text) =>
      setState(() => _query = _query.copyWith(search: text));

  // The meta builder is outermost so its (possibly single-subscription)
  // stream is listened to once, whatever the records stream does. A meta
  // read error only costs the header its run totals.
  @override
  Widget build(BuildContext context) => StreamBuilder<SourceHealthMeta?>(
    stream: _meta,
    builder: (context, metaSnap) => StreamBuilder<List<SourceHealthRecord>>(
      stream: _records,
      builder: (context, snap) {
        if (snap.hasError) return _ReadError(snap.error!);
        final records = snap.data;
        if (records == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (records.isEmpty) {
          return const EmptyState(
            icon: Icons.insights_outlined,
            title: 'No source health yet',
            message: 'The weekly source evaluator has not published results.',
          );
        }
        final meta = metaSnap.hasError ? null : metaSnap.data;
        return _ranking(context, records, meta);
      },
    ),
  );

  Widget _ranking(
    BuildContext context,
    List<SourceHealthRecord> records,
    SourceHealthMeta? meta,
  ) {
    final shown = _query.apply(records);
    String? nameOf(String id) {
      for (final r in records) {
        if (r.id == id) return r.name;
      }
      return null;
    }

    void open(String id) {
      final target = records.firstWhere((r) => r.id == id);
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SourceDetailPage(
            record: target,
            all: records,
            now: widget.clock(),
            profile: _profile,
          ),
        ),
      );
    }

    void edit(HealthQuery q) => setState(() => _query = q);
    final header = <Widget>[
      FreshnessBanner(at: lastEvaluated(records), now: widget.clock()),
      QueryBar(
        query: _query,
        langs: langsOf(records),
        origins: originsOf(records),
        onChanged: edit,
      ),
      FilterBar(query: _query, onChanged: edit),
      if (shown.isEmpty) const Text('No sources match these filters.'),
    ];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            0,
          ),
          child: Column(
            spacing: AppSpacing.sm,
            children: [
              _searchField(),
              if (widget.scoring case final store?) _scoringButton(store),
              CountsHeader(records: records, meta: meta, showing: shown.length),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: header.length + shown.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (_, i) => i < header.length
                ? header[i]
                : SourceCard(
                    record: shown[i - header.length],
                    onOpen: open,
                    nameOf: nameOf,
                    keepScore: _profile.keepScore,
                  ),
          ),
        ),
      ],
    );
  }

  Widget _scoringButton(ScoringProfileStore store) => Align(
    alignment: Alignment.centerLeft,
    child: ValueListenableBuilder<ScoringProfile>(
      valueListenable: store.profile,
      builder: (context, p, _) => OutlinedButton.icon(
        key: const Key('open-scoring'),
        icon: const Icon(Icons.tune),
        label: Text('Scoring · ${p.name}'),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => ScoringPage(store: store)),
        ),
      ),
    ),
  );

  Widget _searchField() => TextField(
    key: const Key('search'),
    controller: _search,
    onChanged: _setSearch,
    decoration: InputDecoration(
      prefixIcon: const Icon(Icons.search),
      hintText: 'Search name, language, reason, metric…',
      suffixIcon: _search.text.isEmpty
          ? null
          : IconButton(
              tooltip: 'Clear search',
              icon: const Icon(Icons.clear),
              onPressed: () {
                _search.clear();
                _setSearch('');
              },
            ),
    ),
  );
}

class _ReadError extends StatelessWidget {
  const new(this.error);

  final Object error;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: AppSpacing.sm,
        children: [
          Text(
            "Couldn't read source health",
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(redactUrlQueries('$error'), textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}
