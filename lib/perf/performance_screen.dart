import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
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
      title: const Text('Performance'),
      actions: [
        TextButton(onPressed: _reset, child: const Text('Reset')),
        const SizedBox(width: AppSpacing.sm),
      ],
    ),
    body: _rows.isEmpty
        ? const EmptyState(
            icon: Icons.speed,
            title: 'No frames measured yet',
            message: 'Use the app; each screen shows up here.',
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
    return ListTile(
      title: Text(s.screen),
      subtitle: Text(
        '${s.janky} of ${s.frames} frames janky ($pct %) · '
        'p50 ${ms(s.p50Micros)} · p90 ${ms(s.p90Micros)} · '
        'p99 ${ms(s.p99Micros)} · worst ${ms(s.worstMicros)} · '
        'budget ${ms(s.budgetMicros)}',
      ),
    );
  }
}
