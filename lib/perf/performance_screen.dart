import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:kartka/core/ui/spoken_label.dart';
import 'package:kartka/perf/frame_stats.dart';
import 'package:kartka/perf/jank_tracker.dart';

/// More → Performance: each screen's frame figures, worst first.
///
/// Shows a snapshot taken when opened (live updates would make this screen
/// its own source of frames). Reset clears the in-memory figures only.
class PerformanceScreen extends StatefulWidget {
  /// Shows [tracker]'s figures.
  const new({required this.tracker, super.key});

  /// The app's jank tracker.
  final JankTracker tracker;

  @override
  State<PerformanceScreen> createState() => _PerformanceScreenState();
}

class _PerformanceScreenState extends State<PerformanceScreen> {
  late List<PerfSummary> _rows = widget.tracker.summaries();

  void _reset() {
    widget.tracker.reset();
    setState(() => _rows = widget.tracker.summaries());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Icon(Icons.speed, semanticLabel: 'Performance'),
      actions: [
        IconButton(
          onPressed: _reset,
          icon: const Icon(Icons.restart_alt, semanticLabel: 'Reset'),
        ),
        const SizedBox(width: AppSpacing.sm),
      ],
    ),
    body: _rows.isEmpty
        ? const EmptyMark(
            icon: Icons.speed,
            semanticLabel: 'No frames measured yet',
          )
        : ListView(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            children: [for (final s in _rows) _PerfTile(s)],
          ),
  );
}

class _PerfTile extends StatelessWidget {
  const new(this.s);

  final PerfSummary s;

  @override
  Widget build(BuildContext context) {
    final pct = (s.jankShare * 100).round();
    String ms(int micros) => '${PerfSummary.ms(micros)} ms';
    final percentiles =
        '${ms(s.p50Micros)} / ${ms(s.p90Micros)} / ${ms(s.p99Micros)}';
    return ListTile(
      title: Text(s.screen),
      subtitle: Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.xs,
        children: [
          _Figure(
            Icons.warning_amber,
            '${s.janky}/${s.frames} ($pct %)',
            '${s.janky} of ${s.frames} frames janky ($pct %)',
          ),
          _Figure(Icons.timer_outlined, percentiles, 'p50 / p90 / p99'),
          _Figure(
            Icons.trending_up,
            ms(s.worstMicros),
            'worst ${ms(s.worstMicros)}',
          ),
          _Figure(
            Icons.flag_outlined,
            ms(s.budgetMicros),
            'budget ${ms(s.budgetMicros)}',
          ),
          if (s.stalls > 0)
            _Figure(
              Icons.hourglass_bottom,
              '${s.stalls} (${ms(s.worstStallMicros)})',
              _stalls(s, ms),
            ),
        ],
      ),
    );
  }
}

/// One figure: a glyph and a number, spoken as [spoken].
class _Figure extends StatelessWidget {
  const new(this.icon, this.value, this.spoken);

  final IconData icon;
  final String value;
  final String spoken;

  @override
  Widget build(BuildContext context) => SpokenLabel(
    semanticLabel: spoken,
    child: ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: AppSpacing.xs),
          Text(value),
        ],
      ),
    ),
  );
}

/// "N stalls (worst X ms)" for a screen with at least one stall.
String _stalls(PerfSummary s, String Function(int) ms) => switch (s.stalls) {
  1 => '1 stall (worst ${ms(s.worstStallMicros)})',
  final n => '$n stalls (worst ${ms(s.worstStallMicros)})',
};
