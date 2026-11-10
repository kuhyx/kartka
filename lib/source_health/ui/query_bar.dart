import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/source_health/labels.dart';
import 'package:kartka/source_health/ranking.dart';
import 'package:kartka/source_health/ui/health_icons.dart';

/// Sort, direction and verdict/lang/origin filters for the ranking.
class QueryBar extends StatelessWidget {
  /// Creates the bar over [query]; [langs]/[origins] are the facet values.
  const new({
    required this.query,
    required this.langs,
    required this.origins,
    required this.onChanged,
    super.key,
  });

  /// Current query.
  final HealthQuery query;

  /// Languages present in the ranking.
  final List<String> langs;

  /// Origins present in the ranking.
  final List<String> origins;

  /// Called with the edited query.
  final ValueChanged<HealthQuery> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: AppSpacing.sm,
    runSpacing: AppSpacing.sm,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      DropdownButton<HealthSort>(
        key: const Key('sort'),
        value: query.sort,
        onChanged: (s) => onChanged(query.copyWith(sort: s)),
        items: [
          for (final s in HealthSort.values)
            DropdownMenuItem(value: s, child: _sortMark(s)),
        ],
      ),
      IconButton(
        key: const Key('reverse'),
        icon: Icon(
          query.reversed ? Icons.arrow_upward : Icons.arrow_downward,
          semanticLabel: query.reversed ? 'Worst first' : 'Best first',
        ),
        onPressed: () => onChanged(query.copyWith(reversed: !query.reversed)),
      ),
      for (final v in HealthVerdict.values)
        FilterChip(
          key: Key('verdict-${v.name}'),
          label: Icon(verdictIcon(v), semanticLabel: verdictLabel(v)),
          selected: query.verdicts.contains(v),
          onSelected: (on) => onChanged(
            query.copyWith(
              verdicts: on
                  ? {...query.verdicts, v}
                  : query.verdicts.difference({v}),
            ),
          ),
        ),
      _facet(
        const Key('lang'),
        query.lang,
        const Icon(Icons.language, semanticLabel: 'All languages'),
        langs,
        Text.new,
        (v) => onChanged(query.copyWith(lang: v, clearLang: v == null)),
      ),
      _facet(
        const Key('origin'),
        query.origin,
        const Icon(Icons.all_inclusive, semanticLabel: 'All origins'),
        origins,
        (o) => Icon(originIcon(o), semanticLabel: originLabel(o)),
        (v) => onChanged(query.copyWith(origin: v, clearOrigin: v == null)),
      ),
    ],
  );

  Widget _facet(
    Key key,
    String? value,
    Widget all,
    List<String> values,
    Widget Function(String) mark,
    ValueChanged<String?> pick,
  ) => DropdownButton<String?>(
    key: key,
    // A filter whose value left the data (after an update) reads as "all".
    value: values.contains(value) ? value : null,
    onChanged: pick,
    items: [
      DropdownMenuItem(child: all),
      for (final v in values) DropdownMenuItem(value: v, child: mark(v)),
    ],
  );
}

/// A sort's glyph; the two latency sorts add their percentile (`p50`).
Widget _sortMark(HealthSort s) {
  final (icon, suffix) = switch (s) {
    HealthSort.rank => (Icons.leaderboard_outlined, null),
    HealthSort.score => (Icons.insights_outlined, null),
    HealthSort.name => (Icons.sort_by_alpha, null),
    HealthSort.latencyP50 => (Icons.speed, 'p50'),
    HealthSort.latencyP95 => (Icons.speed, 'p95'),
    HealthSort.blocking => (Icons.block, null),
    HealthSort.uptime => (metricIcon('Uptime'), null),
    HealthSort.coverage => (metricIcon('Coverage'), null),
    HealthSort.completeness => (metricIcon('Chapters'), null),
    HealthSort.imageWidth => (metricIcon('Image width'), null),
    HealthSort.jpegQuality => (metricIcon('JPEG'), null),
  };
  final glyph = Icon(icon, semanticLabel: s.label);
  if (suffix == null) return glyph;
  return Row(
    mainAxisSize: MainAxisSize.min,
    spacing: AppSpacing.xs,
    children: [glyph, Text(suffix)],
  );
}
