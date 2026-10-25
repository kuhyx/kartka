import 'package:kartka/platform/browser_engine.dart';
import 'package:kartka/platform/engine_scripts.dart';

/// One engine page: the only things a platform has to implement. Android
/// drives a WebView, the desktop drives the wrapper's chromium over HTTP.
abstract interface class EnginePage {
  /// Navigates to [url], sending [headers] with the first request.
  Future<void> navigate(Uri url, Map<String, String> headers);

  /// Evaluates the expression [js] in the current document and returns its
  /// value (raw: run it through [decodeEngineValue]). May throw while a
  /// navigation is in flight.
  Future<Object?> evaluate(String js);

  /// Releases the page.
  Future<void> close();
}

/// Whether the engine may open [url]: `data:`, or http(s) to a host that is
/// not loopback (a page on the wrapper's own origin could call its API).
bool isEngineUrlAllowed(Uri url) {
  if (url.scheme == 'data') return true;
  if (url.scheme != 'http' && url.scheme != 'https') return false;
  final host = url.host.toLowerCase();
  return host.isNotEmpty &&
      host != 'localhost' &&
      !host.endsWith('.localhost') &&
      !host.startsWith('127.') &&
      host != '::1' &&
      host != '0.0.0.0';
}

/// The load loop of docs/DOCS-contracts-webview.md §3, shared by every
/// platform so both behave identically.
class EngineCore {
  /// Opens pages with [openPage]; probes every [pollInterval].
  new(
    this.openPage, {
    this.pollInterval = const Duration(milliseconds: 250),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Creates a fresh page per load.
  final Future<EnginePage> Function() openPage;

  /// Time between probes.
  final Duration pollInterval;

  final DateTime Function() _clock;

  /// Runs [request]; see [KartkaBrowser.load].
  Future<EngineResult> load(EngineRequest request) async {
    if (!isEngineUrlAllowed(request.url)) {
      throw ArgumentError.value(request.url, 'url', 'not allowed in engine');
    }
    final page = await openPage();
    try {
      await page.navigate(request.url, {
        for (final h in request.headers.entries)
          if (h.key.toLowerCase() != 'user-agent') h.key: h.value,
      });
      final (timedOut, response) = await _wait(page, request);
      return _snapshot(
        request.url,
        decodeEngineValue(await page.evaluate(kEngineSnapshotJs)),
        timedOut: timedOut,
        response: response,
      );
    } finally {
      await page.close();
    }
  }

  /// Probes until done or the deadline: (timed out, page response).
  Future<(bool, String?)> _wait(EnginePage page, EngineRequest request) async {
    final deadline = _clock().add(request.timeout);
    final probe = engineProbeJs(request.waitFor);
    String? latest;
    while (true) {
      final s = await _probe(page, probe);
      if (s != null) {
        final challenge = s['challenge'];
        if (challenge is String) {
          final href = s['href'];
          final at = href is String ? Uri.tryParse(href) : null;
          throw ChallengeRequired(at ?? request.url, challenge);
        }
        final complete = s['ready'] == 'complete';
        final response = s['response'];
        latest = response is String ? response : null;
        if (complete && s['ran'] != true) {
          await page.evaluate(kEngineHookJs);
          for (final js in request.scripts) {
            await _run(page, js);
          }
        } else if (complete &&
            s['matched'] == true &&
            (!request.awaitResponse || latest != null)) {
          return (false, latest);
        }
      }
      if (!_clock().isBefore(deadline)) return (true, latest);
      await Future<void>.delayed(pollInterval);
    }
  }

  static Future<Map<String, Object?>?> _probe(
    EnginePage page,
    String js,
  ) async {
    try {
      final v = decodeEngineValue(await page.evaluate(js));
      return v is Map ? v.cast<String, Object?>() : null;
    } on Object {
      return null; // Mid-navigation: the old context is gone. Try again.
    }
  }

  /// A request script that throws is the page's problem (Mangayomi ignores
  /// it too); the wait goes on.
  static Future<void> _run(EnginePage page, String js) async {
    try {
      await page.evaluate(js);
    } on Object {
      return;
    }
  }

  static EngineResult _snapshot(
    Uri requested,
    Object? raw, {
    required bool timedOut,
    required String? response,
  }) {
    final m = raw is Map
        ? raw.cast<String, Object?>()
        : const <String, Object?>{};
    final html = m['html'];
    final resources = m['resources'];
    final status = m['status'];
    final href = m['href'];
    return EngineResult(
      url: (href is String ? Uri.tryParse(href) : null) ?? requested,
      html: html is String ? html : '',
      resources: resources is List
          ? [
              for (final r in resources)
                if (r is String) r,
            ]
          : const [],
      status: status is int ? status : null,
      response: response,
      timedOut: timedOut,
    );
  }
}
