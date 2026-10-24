import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/source_health/feed/source_health_feed.dart';
import 'package:kartka/source_health/model/source_health_record.dart';
import 'package:kartka/source_health/ranking.dart';
import 'package:kartka/source_health/ui/freshness_banner.dart';
import 'package:kartka/source_health/ui/query_bar.dart';
import 'package:kartka/source_health/ui/source_card.dart';
import 'package:kartka/source_health/ui/source_detail_page.dart';

/// The Sources tab: the evaluator's ranking with every metric, sortable and
/// filterable, live from [feed].
class SourcesTab extends StatefulWidget {
  /// Creates the tab; [clock] is injectable for the stale check.
  const new({required this.feed, this.clock = DateTime.now, super.key});

  /// Source of the ranking.
  final SourceHealthFeed feed;

  /// Current time.
  final DateTime Function() clock;

  @override
  State<SourcesTab> createState() => _SourcesTabState();
}

class _SourcesTabState extends State<SourcesTab> {
  late final Stream<List<SourceHealthRecord>> _records = widget.feed.watch();
  HealthQuery _query = const HealthQuery();

  @override
  Widget build(BuildContext context) => StreamBuilder<List<SourceHealthRecord>>(
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
      return _ranking(context, records);
    },
  );

  Widget _ranking(BuildContext context, List<SourceHealthRecord> records) {
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
          ),
        ),
      );
    }

    final header = <Widget>[
      FreshnessBanner(at: lastEvaluated(records), now: widget.clock()),
      QueryBar(
        query: _query,
        langs: langsOf(records),
        origins: originsOf(records),
        onChanged: (q) => setState(() => _query = q),
      ),
      if (shown.isEmpty) const Text('No sources match these filters.'),
    ];
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: header.length + shown.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (_, i) => i < header.length
          ? header[i]
          : SourceCard(
              record: shown[i - header.length],
              onOpen: open,
              nameOf: nameOf,
            ),
    );
  }
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
          Text('$error', textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}
