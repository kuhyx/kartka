import 'package:design_system/design_system.dart';
import 'package:kartka/app/fit_pages.dart';
import 'package:kartka/app/wait_watch.dart';
import 'package:kartka/core/redact.dart';
import 'package:kartka/core/ui/spoken_label.dart';
import 'package:kartka/source_health/feed/source_health_feed.dart';
import 'package:kartka/source_health/install/keep_reconciler.dart';
import 'package:kartka/source_health/install/source_installs.dart';
import 'package:kartka/source_health/model/source_health_meta.dart';
import 'package:kartka/source_health/model/source_health_record.dart';
import 'package:kartka/source_health/ranking.dart';
import 'package:kartka/source_health/scoring/profile.dart';
import 'package:kartka/source_health/scoring/profile_store.dart';
import 'package:kartka/source_health/ui/filters_sheet.dart';
import 'package:kartka/source_health/ui/freshness_banner.dart';
import 'package:kartka/source_health/ui/source_detail_page.dart';
import 'package:kartka/source_health/ui/source_sheets.dart';
import 'package:kartka/source_health/ui/source_tile.dart';
import 'package:material_ui/material_ui.dart';

/// The Sources tab: the evaluator's ranking with every metric, searchable,
/// sortable and filterable, live from [feed].
class SourcesTab extends StatefulWidget {
  /// Creates the tab; [clock] is injectable for the stale check.
  const new({
    required this.feed,
    this.scoring,
    this.clock = DateTime.now,
    this.installs,
    this.autoInstall,
    this.onMigrate,
    super.key,
  });

  /// The Keep auto-install; its status shows above the ranking.
  final KeepReconciler? autoInstall;

  /// Opens "Migrate to better sources"; null hides the button.
  final void Function(BuildContext context)? onMigrate;

  /// Install / Open state of every source; null shows no action buttons.
  final SourceInstalls? installs;

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
  // rebuilt (and the text must stay in step with it). A notifier, so the
  // filters sheet edits the same query the grid reads.
  final _search = TextEditingController();
  final _query = ValueNotifier<HealthQuery>(const HealthQuery());

  @override
  void dispose() {
    _search.dispose();
    _query.dispose();
    super.dispose();
  }

  ScoringProfile get _profile =>
      widget.scoring?.profile.value ?? defaultScoringProfile;

  void _setSearch(String text) =>
      _query.value = _query.value.copyWith(search: text);

  // The meta builder is outermost so its (possibly single-subscription)
  // stream is listened to once, whatever the records stream does. A meta
  // read error only costs the sheet its run totals.
  @override
  Widget build(BuildContext context) => StreamBuilder<SourceHealthMeta?>(
    stream: _meta,
    builder: (context, metaSnap) => StreamBuilder<List<SourceHealthRecord>>(
      stream: _records,
      builder: (context, snap) {
        if (snap.hasError) return _ReadError(snap.error!);
        final records = snap.data;
        if (records == null) return const WaitWatch.centered('sources.load');
        if (records.isEmpty) {
          return const EmptyMark(
            icon: Icons.insights_outlined,
            semanticLabel: 'No source health yet',
          );
        }
        final meta = metaSnap.hasError ? null : metaSnap.data;
        return ValueListenableBuilder<HealthQuery>(
          valueListenable: _query,
          builder: (context, q, _) => _ranking(context, records, meta, q),
        );
      },
    ),
  );

  void _open(BuildContext context, List<SourceHealthRecord> all, String id) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SourceDetailPage(
            record: all.firstWhere((r) => r.id == id),
            all: all,
            now: widget.clock(),
            profile: _profile,
            installs: widget.installs,
          ),
        ),
      );

  void _menu(BuildContext context, List<SourceHealthRecord> all, String id) =>
      showSourceSheet(
        context,
        all: all,
        id: id,
        keepScore: _profile.keepScore,
        installs: widget.installs,
        onOpen: (target) => _open(context, all, target),
      );

  void _filters(
    BuildContext context,
    List<SourceHealthRecord> all,
    SourceHealthMeta? meta,
  ) => showFiltersSheet(
    context,
    records: all,
    meta: meta,
    query: _query,
    now: widget.clock(),
    scoring: widget.scoring,
    autoInstall: widget.autoInstall,
    onMigrate: widget.onMigrate,
  );

  Widget _ranking(
    BuildContext context,
    List<SourceHealthRecord> records,
    SourceHealthMeta? meta,
    HealthQuery q,
  ) {
    final shown = q.apply(records);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: AppSpacing.sm,
            children: [
              Row(
                spacing: AppSpacing.sm,
                children: [
                  Expanded(child: _searchField()),
                  FiltersButton(
                    query: q,
                    onPressed: () => _filters(context, records, meta),
                  ),
                ],
              ),
              FreshnessBanner(
                at: lastEvaluated(records),
                now: widget.clock(),
                compact: true,
              ),
            ],
          ),
        ),
        Expanded(
          child: shown.isEmpty
              ? const EmptyMark(
                  icon: Icons.filter_list_off,
                  semanticLabel: 'No match',
                )
              : FitPages(
                  columns: 2,
                  minSquare: 0.45,
                  itemCount: shown.length,
                  itemBuilder: (_, i) => SourceTile(
                    record: shown[i],
                    onOpen: () => _open(context, records, shown[i].id),
                    onMenu: () => _menu(context, records, shown[i].id),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _searchField() => TextField(
    key: const Key('search'),
    controller: _search,
    onChanged: _setSearch,
    decoration: InputDecoration(
      prefixIcon: const Icon(Icons.search, semanticLabel: 'Search sources'),
      suffixIcon: _search.text.isEmpty
          ? null
          : IconButton(
              icon: const Icon(Icons.clear, semanticLabel: 'Clear search'),
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
          Icon(
            Icons.error_outline,
            size: 48,
            color: Theme.of(context).colorScheme.error,
            semanticLabel: "Couldn't read source health",
          ),
          Text(redactUrlQueries('$error'), textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}
