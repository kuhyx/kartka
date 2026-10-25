import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

/// Port: told which screen is on top whenever it changes (DOCS-contracts §3).
///
/// Features offer one as a service; the app shell reports to every one.
abstract interface class ScreenObserver {
  /// The top screen is now [pattern]: the go_router route pattern
  /// (`/read/:sourceId/:mangaUrl/:chapterUrl`), never the concrete location,
  /// so ids, URLs and titles never leave the router.
  void screenChanged(String pattern);
}

/// Pattern reported when go_router knows no pattern for the top route.
const unknownScreenPattern = '?';

/// Reports [router]'s top route pattern to [observers] on every change
/// (once per distinct pattern). Returns the function that stops reporting.
VoidCallback reportScreens(
  GoRouter router,
  List<ScreenObserver> Function() observers,
) {
  final delegate = router.routerDelegate;
  String? last;
  void report() {
    if (delegate.currentConfiguration.isEmpty) return;
    final path = delegate.state.fullPath;
    final pattern = path == null || path.isEmpty ? unknownScreenPattern : path;
    if (pattern == last) return;
    last = pattern;
    for (final o in observers()) {
      o.screenChanged(pattern);
    }
  }

  delegate.addListener(report);
  return () => delegate.removeListener(report);
}
