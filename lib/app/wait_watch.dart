import 'package:kartka/app/scope.dart';
import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:material_ui/material_ui.dart';

/// Times how long its [child] (a loader or spinner) stays on screen and
/// reports a wait over a second as `perf.slow` for [operation]
/// (`reader.open`, `library.load`), so the PC files a ticket to cut it.
///
/// The one shared hook for every loader: wrap the spinner instead of timing
/// the future at each call site. Without a [KartkaScope] (a bare widget in a
/// test) it only shows [child].
class WaitWatch extends StatefulWidget {
  /// Watches [child] as a wait on [operation].
  const new({required this.operation, required this.child, super.key});

  /// Watches a centred spinner, the usual full-page loader.
  const new centered(this.operation, {super.key})
    : child = const Center(child: CircularProgressIndicator());

  /// What the user waits for, dotted by area (`reader.page`). Never an id.
  final String operation;

  /// The loader shown while waiting.
  final Widget child;

  @override
  State<WaitWatch> createState() => _WaitWatchState();
}

class _WaitWatchState extends State<WaitWatch> with WidgetsBindingObserver {
  late final SlowWaitReporter _reporter; // Set whenever the observer is added.
  SlowWait? _wait;

  @override
  void initState() {
    super.initState();
    final scope = context.getInheritedWidgetOfExactType<KartkaScope>();
    if (scope == null) return;
    _reporter = SlowWaitReporter.of(
      DiagnosticsLog.of(scope.platform.diagnostics),
    );
    _wait = _reporter.begin(widget.operation);
    WidgetsBinding.instance.addObserver(this);
  }

  /// A backgrounded app is not a wait the user sees: the wait ends when the
  /// app leaves the foreground and a new one starts when it returns.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _wait ??= _reporter.begin(widget.operation);
    } else {
      _wait?.end();
      _wait = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _wait?.end();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
