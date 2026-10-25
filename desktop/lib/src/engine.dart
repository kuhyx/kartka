import 'dart:async';
import 'dart:io';

import 'package:kartka_desktop/src/cdp.dart';
import 'package:kartka_desktop/src/chromium.dart';
import 'package:kartka_desktop/src/engine_host.dart';
import 'package:kartka_desktop/src/protocol.dart';

export 'package:kartka_desktop/src/engine_host.dart';

/// [EngineHost] on a lazily started headless chromium.
class ChromiumEngineHost implements EngineHost {
  /// Uses browser [exe] (empty: none) on [profile]; [headlessOnly] refuses
  /// the visible window (the agent instance).
  new({
    required this.exe,
    required this.profile,
    required this.hosts,
    required this.headlessOnly,
    this.maxPages = 8,
    this.allowLoopback = false,
  });

  /// Browser executable.
  final String exe;

  /// Engine profile directory.
  final String profile;

  /// Registered cookie hosts.
  final EngineHosts hosts;

  /// Whether the visible window is refused.
  final bool headlessOnly;

  /// Open pages kept at most; the oldest closes first.
  final int maxPages;

  /// Tests only: lets pages reach loopback hosts, except [protectedPorts].
  final bool allowLoopback;

  /// Loopback ports no page may ever load (the real app's wrapper; the
  /// server adds its own port on start): a page there could call the API.
  final Set<int> protectedPorts = {kartkaPort};

  Future<HeadlessChromium>? _engine;
  Process? _window;
  bool _opening = false;

  bool get _windowBusy => _window != null || _opening;
  final Map<String, ({String target, String session})> _pages = {};
  int _seq = 0;

  Future<CdpClient> _cdp() async {
    if (exe.isEmpty) throw const EngineError(503, 'no-browser');
    if (_windowBusy) throw const EngineError(409, 'window-open');
    final running = _engine ??= HeadlessChromium.launch(exe, profile);
    try {
      final engine = await running;
      if (!engine.cdp.isClosed) return engine.cdp;
    } on Object {
      _engine = null;
      rethrow;
    }
    _engine = null;
    return await _cdp();
  }

  ({String target, String session}) _page(String id) =>
      _pages[id] ?? (throw const EngineError(404, 'no-page'));

  @override
  Future<String> createPage() async {
    final cdp = await _cdp();
    if (_pages.length >= maxPages) await closePage(_pages.keys.first);
    final target = await cdp.call(
      'Target.createTarget',
      params: {'url': 'about:blank'},
    );
    final targetId = '${target['targetId']}';
    final session = await preparePage(
      cdp,
      targetId,
      blockedLoopbackPatterns(protectedPorts, allowLoopback: allowLoopback),
    );
    final id = 'p${++_seq}';
    _pages[id] = (target: targetId, session: session);
    return id;
  }

  @override
  Future<void> navigate(String id, Uri url, Map<String, String> headers) async {
    final page = _page(id);
    final cdp = await _cdp();
    final extra = {
      for (final h in headers.entries)
        if (h.key.toLowerCase() != 'referer' &&
            h.key.toLowerCase() != 'user-agent')
          h.key: h.value,
    };
    final referrer = [
      for (final h in headers.entries)
        if (h.key.toLowerCase() == 'referer') h.value,
    ].firstOrNull;
    await cdp.call(
      'Network.setExtraHTTPHeaders',
      params: {'headers': extra},
      sessionId: page.session,
    );
    final r = await cdp.call(
      'Page.navigate',
      params: {'url': '$url', 'referrer': ?referrer},
      sessionId: page.session,
    );
    final error = r['errorText'];
    if (error is String && error.isNotEmpty) throw EngineError(502, error);
  }

  @override
  Future<Object?> evaluate(String id, String expression) async {
    final page = _page(id);
    final r = await (await _cdp()).call(
      'Runtime.evaluate',
      params: {
        'expression': expression,
        'returnByValue': true,
        'awaitPromise': true,
      },
      sessionId: page.session,
    );
    if (r['exceptionDetails'] case final Map<Object?, Object?> e) {
      final ex = e['exception'];
      final text = ex is Map ? ex['description'] : e['text'];
      throw EngineError(422, '${text ?? 'exception'}'.split('\n').first);
    }
    final value = r['result'];
    return value is Map ? value['value'] : null;
  }

  @override
  Future<void> closePage(String id) async {
    final page = _pages.remove(id);
    final engine = _engine;
    if (page == null || engine == null) return;
    try {
      await (await engine).cdp.call(
        'Target.closeTarget',
        params: {'targetId': page.target},
      );
    } on CdpException {
      return; // Already gone with its browser.
    }
  }

  @override
  Future<void> open(Uri url) async {
    if (headlessOnly) throw const EngineError(409, 'headless-only');
    if (exe.isEmpty) throw const EngineError(503, 'no-browser');
    // Until the window owns the profile, no headless relaunch may take it.
    _opening = true;
    final Process w;
    try {
      await _closeWindow();
      await _stopEngine();
      w = await Process.start(exe, windowArgs(profile, url));
    } finally {
      _opening = false;
    }
    _window = w;
    // kuhy may close the window himself before pressing Done.
    unawaited(
      w.exitCode.then((_) {
        if (identical(_window, w)) _window = null;
      }),
    );
  }

  @override
  Future<void> finish(Uri url) async {
    await _closeWindow();
    hosts.add(url.host);
  }

  @override
  Future<String?> cookieHeader(Uri url) async {
    if (!hosts.covers(url) || _windowBusy || exe.isEmpty) return null;
    final r = await (await _cdp()).call('Storage.getCookies');
    final cookies = r['cookies'];
    final header = cookieHeaderFor(
      url,
      cookies is List ? cookies : [],
      DateTime.now(),
    );
    return header.isEmpty ? null : header;
  }

  Future<void> _closeWindow() async {
    final w = _window;
    _window = null;
    if (w == null) return;
    w.kill(); // SIGTERM: chromium flushes its cookies before exiting.
    await w.exitCode.timeout(
      const Duration(seconds: 10),
      // coverage:ignore-start
      // Only a browser that ignores SIGTERM for 10 s gets here; tests
      // cannot wait that long.
      onTimeout: () {
        w.kill(ProcessSignal.sigkill);
        return -1;
      },
      // coverage:ignore-end
    );
  }

  Future<void> _stopEngine() async {
    final running = _engine;
    _engine = null;
    _pages.clear();
    if (running == null) return;
    try {
      await (await running).stop();
    } on Object {
      return; // It never started.
    }
  }

  @override
  Future<void> stop() async {
    await _closeWindow();
    await _stopEngine();
  }
}
