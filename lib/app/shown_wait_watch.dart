import 'package:crdt_sync_flutter/crdt_sync_flutter.dart' show WaitWatch;
import 'package:material_ui/material_ui.dart';

/// A [WaitWatch] that times its loader only while the loader is on screen.
///
/// The shared watch times from mount to unmount. A page stays mounted when
/// a route is pushed over it (the reader over a manga's details) or its tab
/// is left, and a loader there kept timing a wait nobody saw: a
/// `details.refresh` reported from the reader's route (13c3c635), or a
/// 153 s one. The navigator turns tickers off for a covered page and the
/// shell for a hidden tab, so [TickerMode] says whether the loader shows.
/// Uncovered, the watch starts again: what is still loading is a new wait.
class ShownWaitWatch extends StatelessWidget {
  /// Times [child] as a wait on [operation] while it is shown.
  const new({required this.operation, required this.child, super.key});

  /// Times a centred spinner, the usual full-page loader.
  const new centered(this.operation, {super.key})
    : child = const Center(child: CircularProgressIndicator());

  /// What the user waits for (`WaitWatch.operation`).
  final String operation;

  /// The loader, shown covered or not.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!TickerMode.valuesOf(context).enabled) return child;
    return WaitWatch(operation: operation, child: child);
  }
}
