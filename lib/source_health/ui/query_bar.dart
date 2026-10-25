import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/source_health/labels.dart';
import 'package:kartka/source_health/ranking.dart';

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
            DropdownMenuItem(value: s, child: Text('Sort: ${s.label}')),
        ],
      ),
      IconButton(
        key: const Key('reverse'),
        tooltip: query.reversed ? 'Worst first' : 'Best first',
        icon: Icon(query.reversed ? Icons.arrow_upward : Icons.arrow_downward),
        onPressed: () => onChanged(query.copyWith(reversed: !query.reversed)),
      ),
      for (final v in HealthVerdict.values)
        FilterChip(
          label: Text(verdictLabel(v)),
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
        'All languages',
        langs,
        (v) => v,
        (v) => onChanged(query.copyWith(lang: v, clearLang: v == null)),
      ),
      _facet(
        const Key('origin'),
        query.origin,
        'All origins',
        origins,
        originLabel,
        (v) => onChanged(query.copyWith(origin: v, clearOrigin: v == null)),
      ),
    ],
  );

  Widget _facet(
    Key key,
    String? value,
    String all,
    List<String> values,
    String Function(String) label,
    ValueChanged<String?> pick,
  ) => DropdownButton<String?>(
    key: key,
    // A filter whose value left the data (after an update) reads as "all".
    value: values.contains(value) ? value : null,
    onChanged: pick,
    items: [
      DropdownMenuItem(child: Text(all)),
      for (final v in values) DropdownMenuItem(value: v, child: Text(label(v))),
    ],
  );
}
