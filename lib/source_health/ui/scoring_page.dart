import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/core/ui/section_mark.dart';
import 'package:kartka/source_health/format.dart';
import 'package:kartka/source_health/reason_filter.dart';
import 'package:kartka/source_health/scoring/profile.dart';
import 'package:kartka/source_health/scoring/profile_store.dart';
import 'package:kartka/source_health/thresholds.dart';
import 'package:kartka/source_health/ui/health_icons.dart';

const _weightLabels = [
  'Coverage (with complete chapters)',
  'Uptime',
  'Image quality',
  'Speed (latency)',
];

/// The Scoring settings page: the weights of the four score parts, the
/// pages-load multiplier, the keep bar and the cut switches of the active
/// [ScoringProfile]. Edits re-score the ranking and Browse live and sync to
/// every device and the evaluator.
class ScoringPage extends StatelessWidget {
  /// Creates the page over [store].
  const new({required this.store, super.key});

  /// The active profile.
  final ScoringProfileStore store;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Icon(Icons.tune, semanticLabel: 'Scoring')),
    body: ValueListenableBuilder<ScoringProfile>(
      valueListenable: store.profile,
      builder: (context, p, _) => ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Icon(
              p.isDefault ? Icons.insights_outlined : Icons.sync,
              key: const Key('profile-name'),
              semanticLabel: p.isDefault
                  ? 'Using the evaluator defaults'
                  : 'Using a custom profile, synced',
            ),
          ),
          const SectionMark(
            Icons.balance,
            semanticLabel:
                'Score weights. A weight of 0 turns a part off; weights are '
                'rescaled to add up to 100 %.',
          ),
          for (final (i, label) in _weightLabels.indexed)
            _WeightRow(index: i, label: label, profile: p, store: store),
          const SectionMark(
            Icons.auto_stories_outlined,
            semanticLabel: 'Pages load',
          ),
          SwitchListTile(
            key: const Key('pages-multiplier'),
            title: const Icon(
              Icons.calculate_outlined,
              semanticLabel:
                  'Pages load multiplies the score: a source whose pages '
                  'never load then scores 0.',
            ),
            value: p.pagesLoadMultiplier,
            onChanged: (on) => store.save(p.copyWith(pagesLoadMultiplier: on)),
          ),
          const SectionMark(
            Icons.check_circle_outline,
            semanticLabel: 'Keep bar',
          ),
          Text(
            '≥ ${p.keepScore.toStringAsFixed(2)}',
            semanticsLabel: 'Keep at score ≥ ${p.keepScore.toStringAsFixed(2)}',
          ),
          Slider(
            key: const Key('keep-score'),
            value: p.keepScore,
            divisions: 20,
            label: p.keepScore.toStringAsFixed(2),
            onChanged: (v) => store.preview(p.copyWith(keepScore: v)),
            onChangeEnd: (_) => store.save(store.profile.value),
          ),
          const SectionMark(
            Icons.content_cut,
            semanticLabel:
                'Cut switches. A switch cuts every source its reason applies '
                'to, whatever its score.',
          ),
          for (final reason in kCutWireNames.keys)
            SwitchListTile(
              key: Key('cut-${kCutWireNames[reason]}'),
              title: Align(
                alignment: Alignment.centerLeft,
                child: Icon(
                  reasonIcon(reason),
                  semanticLabel:
                      'Cut: ${reason.label}. ${_cutExplanations[reason]}',
                ),
              ),
              value: p.cuts.contains(reason),
              onChanged: (on) => store.save(
                p.copyWith(
                  cuts: on ? {...p.cuts, reason} : p.cuts.difference({reason}),
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton.filledTonal(
              key: const Key('reset-scoring'),
              style: IconButton.styleFrom(minimumSize: const Size.square(48)),
              icon: const Icon(
                Icons.restart_alt,
                semanticLabel: 'Reset to evaluator defaults',
              ),
              onPressed: p.isDefault ? null : store.reset,
            ),
          ),
        ],
      ),
    ),
  );
}

/// One line per cut switch ([kCutWireNames]; a subset is a graded score
/// penalty instead, never a switch).
final _cutExplanations = <HealthReason, String>{
  HealthReason.blocking:
      'A Cloudflare challenge, captcha, 403 or 429 was seen.',
  HealthReason.coverage:
      'Fewer than ${pct(HealthThresholds.minCoverageRatio)} of the reference '
      'titles.',
  HealthReason.uptime:
      'Fewer than ${pct(HealthThresholds.minUptimeRatio)} of the uptime '
      'probes answered (once the window is complete).',
  HealthReason.browserEngine: 'Its extension needs a browser engine.',
  HealthReason.pagesNeverLoad: 'No sampled chapter loaded all its pages.',
};

class _WeightRow extends StatelessWidget {
  const new({
    required this.index,
    required this.label,
    required this.profile,
    required this.store,
  });

  final int index;
  final String label;
  final ScoringProfile profile;
  final ScoringProfileStore store;

  @override
  Widget build(BuildContext context) {
    final weights = profile.weights;
    final value = weights.values[index];
    final share = weights.total > 0 ? weights.normalised.values[index] : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconValue(
          metricIcon(label),
          pct(share),
          semanticLabel: '$label: share of the score',
        ),
        Row(
          children: [
            Expanded(
              child: Slider(
                key: Key('weight-$index'),
                value: value,
                divisions: 20,
                label: value.toStringAsFixed(2),
                semanticFormatterCallback: (v) => '$label weight ${pct(v)}',
                onChanged: (v) {
                  final next = weights.withValue(index, v);
                  // All zero is invalid: the slider snaps back instead.
                  if (next.total > 0) {
                    store.preview(profile.copyWith(weights: next));
                  }
                },
                onChangeEnd: (_) => store.save(store.profile.value),
              ),
            ),
            IconButton(
              key: Key('only-$index'),
              icon: const Icon(Icons.filter_1, semanticLabel: 'Only this'),
              onPressed: () => store.save(
                profile.copyWith(
                  weights: ScoreWeights.fromValues([
                    for (var j = 0; j < ScoreWeights.keys.length; j++)
                      if (j != index) 0.0 else if (value > 0) value else 1.0,
                  ]),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
