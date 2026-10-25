import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/source_health/format.dart';
import 'package:kartka/source_health/model/source_health_meta.dart';

/// Candidates the evaluator did not test, grouped by index and reason;
/// each group expands to the names.
class SkippedPage extends StatelessWidget {
  /// Creates the page for [meta].
  const new({required this.meta, super.key});

  /// The run summary.
  final SourceHealthMeta meta;

  @override
  Widget build(BuildContext context) {
    final at = meta.generatedAt;
    final run = [
      if (meta.runId case final id?) 'Run $id',
      if (at != null) instant(at),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Skipped candidates')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          if (run.isNotEmpty) Text(run.join(' · ')),
          if (meta.skipped.isEmpty) const Text('Nothing was skipped.'),
          for (final g in meta.skipped)
            ExpansionTile(
              title: Text('${g.index} · ${g.reason} · ${g.count}'),
              children: [
                if (g.names.isEmpty)
                  const ListTile(title: Text('No names recorded.')),
                for (final name in g.names)
                  ListTile(dense: true, title: Text(name)),
              ],
            ),
        ],
      ),
    );
  }
}
