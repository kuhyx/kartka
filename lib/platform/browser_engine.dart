/// `KartkaPlatform.browser`: the headless engine and "Open in WebView"
/// (docs/DOCS-contracts-webview.md §3).
library;

import 'package:flutter/widgets.dart';
import 'package:kartka/core/source/challenge.dart';

export 'package:kartka/core/source/challenge.dart';

/// One page load in the engine.
class EngineRequest {
  /// Loads [url]; see the contract §3 for the order of events.
  new({
    required this.url,
    this.headers = const {},
    this.scripts = const [],
    this.waitFor,
    this.awaitResponse = false,
    Duration timeout = defaultTimeout,
  }) : timeout = timeout > maxTimeout ? maxTimeout : timeout;

  /// Used when the caller gives no timeout.
  static const defaultTimeout = Duration(seconds: 20);

  /// Longest load: below the plugin host-call timeout (30 s).
  static const maxTimeout = Duration(seconds: 25);

  /// The page (http(s) to a non-loopback host, or `data:`).
  final Uri url;

  /// Headers for the first navigation; `User-Agent` is dropped.
  final Map<String, String> headers;

  /// Run in order in every completed document (return values discarded).
  final List<String> scripts;

  /// CSS selector that must match before the snapshot, if any.
  final String? waitFor;

  /// Whether to wait for `kartka.respond(...)` / Mangayomi's `setResponse`.
  final bool awaitResponse;

  /// Deadline for the whole load.
  final Duration timeout;
}

/// What the engine saw.
class EngineResult {
  /// Creates a result.
  const new({
    required this.url,
    required this.html,
    this.resources = const [],
    this.status,
    this.response,
    this.timedOut = false,
  });

  /// Final document URL (after redirects).
  final Uri url;

  /// `document.documentElement.outerHTML`.
  final String html;

  /// Resource URLs the page requested, plus `img[src]`, deduplicated.
  final List<String> resources;

  /// Main document status, when the engine reports it.
  final int? status;

  /// The page-supplied response string, if any.
  final String? response;

  /// Whether the deadline passed before the wait condition held.
  final bool timedOut;

  /// JSON handed to plugins (`kartka.browser.load`).
  Map<String, Object?> toJson() => {
    'url': '$url',
    'status': status,
    'html': html,
    'resources': resources,
    'response': response,
    'timedOut': timedOut,
  };
}

/// No engine on this platform (or no chromium next to the wrapper).
class EngineUnavailable implements Exception {
  /// Creates the error with a short [reason].
  const new(this.reason);

  /// Why (`no-browser`, `headless-only`, ...).
  final String reason;

  @override
  String toString() => 'Browser engine unavailable: $reason';
}

/// The browser service (contract §3). Android: webview_flutter; desktop:
/// the wrapper's headless chromium.
abstract interface class KartkaBrowser {
  /// Renders [request]. Throws [ChallengeRequired] on an interstitial and
  /// [EngineUnavailable] when there is no engine.
  Future<EngineResult> load(EngineRequest request);

  /// Whether "Open in WebView" is an in-app page ([buildView]) rather than
  /// an external window ([openExternal]).
  bool get inApp;

  /// The in-app interactive view on [url] (only when [inApp]).
  Widget buildView(Uri url);

  /// Opens the external interactive window on [url] (only when not
  /// [inApp]).
  Future<void> openExternal(Uri url);

  /// kuhy is done on [url]: from now on kartka's HTTP to its host carries
  /// the site's cookies.
  Future<void> finish(Uri url);

  /// Wraps the app so hidden engine views can be mounted (Android).
  Widget host(Widget child);
}

/// The default: no engine anywhere.
class UnavailableBrowser implements KartkaBrowser {
  /// Creates the placeholder.
  const new();

  static const _none = EngineUnavailable('no browser engine on this platform');

  @override
  Future<EngineResult> load(EngineRequest request) async => throw _none;

  @override
  bool get inApp => false;

  @override
  Widget buildView(Uri url) => const SizedBox.shrink();

  @override
  Future<void> openExternal(Uri url) async => throw _none;

  @override
  Future<void> finish(Uri url) async => throw _none;

  @override
  Widget host(Widget child) => child;
}
