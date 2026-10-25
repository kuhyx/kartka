import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/source_health/format.dart';
import 'package:kartka/source_health/reason_filter.dart';
import 'package:kartka/source_health/scoring/profile.dart';
import 'package:kartka/source_health/scoring/profile_store.dart';
import 'package:kartka/source_health/thresholds.dart';

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
    appBar: AppBar(title: const Text('Scoring')),
    body: ValueListenableBuilder<ScoringProfile>(
      valueListenable: store.profile,
      builder: (context, p, _) => ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Text(
            p.isDefault
                ? 'Using the evaluator defaults.'
                : 'Using a custom profile (synced to every device and the '
                      'evaluator).',
          ),
          const SectionHeader('Score weights'),
          const Text(
            'A weight of 0 turns a part off. Weights are rescaled to add up '
            'to 100 %, and at least one must stay above 0.',
          ),
          for (final (i, label) in _weightLabels.indexed)
            _WeightRow(index: i, label: label, profile: p, store: store),
          const SectionHeader('Pages load'),
          SwitchListTile(
            key: const Key('pages-multiplier'),
            title: const Text('Pages load multiplies the score'),
            subtitle: const Text(
              'A source whose pages never load then scores 0.',
            ),
            value: p.pagesLoadMultiplier,
            onChanged: (on) => store.save(p.copyWith(pagesLoadMultiplier: on)),
          ),
          const SectionHeader('Keep bar'),
          Text('Keep at score ≥ ${p.keepScore.toStringAsFixed(2)}'),
          Slider(
            key: const Key('keep-score'),
            value: p.keepScore,
            divisions: 20,
            label: p.keepScore.toStringAsFixed(2),
            onChanged: (v) => store.preview(p.copyWith(keepScore: v)),
            onChangeEnd: (_) => store.save(store.profile.value),
          ),
          const SectionHeader('Cut switches'),
          const Text(
            'A switch cuts every source its reason applies to, whatever its '
            'score. All off: the score alone decides.',
          ),
          for (final reason in kCutWireNames.keys)
            SwitchListTile(
              key: Key('cut-${kCutWireNames[reason]}'),
              title: Text('Cut: ${reason.label}'),
              subtitle: Text(_cutExplanations[reason]!),
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
            child: FilledButton.tonalIcon(
              key: const Key('reset-scoring'),
              icon: const Icon(Icons.restart_alt),
              label: const Text('Reset to evaluator defaults'),
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
        Row(
          children: [
            Expanded(child: Text(label)),
            Text('${pct(share)} of the score'),
          ],
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
            TextButton(
              key: Key('only-$index'),
              onPressed: () => store.save(
                profile.copyWith(
                  weights: ScoreWeights.fromValues([
                    for (var j = 0; j < ScoreWeights.keys.length; j++)
                      if (j != index) 0.0 else if (value > 0) value else 1.0,
                  ]),
                ),
              ),
              child: const Text('Only this'),
            ),
          ],
        ),
      ],
    );
  }
}
