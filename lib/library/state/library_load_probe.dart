import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:kartka/core/diagnostics/startup_marks.dart';

/// What the first library paint of a launch waited on (library.load
/// a133bbb8): the grid marks `library.wait` when its spinner shows, and
/// [shown] runs after the first paint with rows. Every launch logs its
/// marks as a device-only `perf.startup` line; a spinner shown 1 s or more
/// also uploads a `library.load` line naming the slowest step in it
/// (no times: the `perf.slow` report and `perf.startup` carry them).
class LibraryLoadProbe {
  /// Reads [marks] and writes through [reporter].
  new(this.marks, this.reporter);

  /// The launch marks.
  final StartupMarks marks;

  /// Where the lines go.
  final ErrorReporter reporter;

  bool _done = false;

  /// The first paint with rows; later calls do nothing.
  void shown() {
    if (_done) return;
    _done = true;
    marks.mark('library.shown');
    reporter.report('perf.startup', marks.describe());
    final waited = marks.since('library.wait', 'library.shown');
    final slow = marks.slowestSince('library.wait');
    if (waited == null || waited < 1000 || slow == null) return;
    // No times in it: each distinct text is its own board ticket.
    reporter.report(
      'library.load',
      'LibraryProbe: library waited on ${slow.step}',
    );
  }
}
