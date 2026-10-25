import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:kartka_desktop/src/browser.dart';
import 'package:kartka_desktop/src/cdp.dart';
import 'package:path/path.dart' as p;

/// The engine's browser: `$KARTKA_ENGINE_BROWSER`, else the real
/// `/usr/bin/chromium` (not the `/usr/local/bin` wrapper), else the app's
/// browser list; `''` when none.
String findEngineBrowser({
  Map<String, String>? env,
  bool Function(String path)? exists,
}) {
  final test = exists ?? (String path) => File(path).existsSync();
  final override = (env ?? Platform.environment)['KARTKA_ENGINE_BROWSER'];
  for (final c in [override ?? '', '/usr/bin/chromium']) {
    if (c.isNotEmpty && test(c)) return c;
  }
  return findBrowser(exists: test);
}

/// [env] without the live display: a mis-flagged browser then has nowhere
/// to open a window.
Map<String, String> headlessEnvironment(Map<String, String> env) => {
  for (final e in env.entries)
    if (e.key != 'DISPLAY' && e.key != 'WAYLAND_DISPLAY') e.key: e.value,
};

/// Arguments of the headless engine on [profile].
List<String> headlessArgs(String profile) => [
  '--headless=new',
  '--remote-debugging-port=0',
  '--remote-debugging-address=127.0.0.1',
  '--user-data-dir=$profile',
  // Drops command-line extensions from chromium-flags.conf.
  '--disable-extensions',
  '--no-first-run',
  '--no-default-browser-check',
  '--password-store=basic',
  '--mute-audio',
  'about:blank',
];

/// Arguments of the visible "Open in WebView" window on [profile].
List<String> windowArgs(String profile, Uri url) => [
  '--app=$url',
  '--user-data-dir=$profile',
  '--class=kartka-webview',
  '--no-first-run',
  '--no-default-browser-check',
  '--password-store=basic',
  '--disable-extensions',
];

/// A running headless chromium the wrapper owns.
class HeadlessChromium {
  new _(this.process, this.cdp);

  /// Starts [exe] headless on [profile] and attaches over CDP. Refuses
  /// (and kills) anything whose `/json/version` is not `HeadlessChrome`.
  static Future<HeadlessChromium> launch(String exe, String profile) async {
    Directory(profile).createSync(recursive: true);
    final portFile = File(p.join(profile, 'DevToolsActivePort'));
    if (portFile.existsSync()) portFile.deleteSync();
    final process = await Process.start(
      exe,
      headlessArgs(profile),
      environment: headlessEnvironment(Platform.environment),
      includeParentEnvironment: false,
    );
    unawaited(process.stdout.drain<void>());
    unawaited(process.stderr.drain<void>());
    try {
      final port = await _readPort(portFile, process);
      final version = await _version(port);
      if (!'${version['User-Agent']}'.contains('HeadlessChrome')) {
        throw StateError('engine browser is not headless; refusing it');
      }
      final ws = Uri.parse('${version['webSocketDebuggerUrl']}');
      return HeadlessChromium._(process, await CdpClient.connect(ws));
    } on Object {
      process.kill(ProcessSignal.sigkill);
      rethrow;
    }
  }

  /// The browser process.
  final Process process;

  /// Browser-level CDP connection.
  final CdpClient cdp;

  static Future<int> _readPort(File file, Process process) async {
    var exited = false;
    unawaited(process.exitCode.then((_) => exited = true));
    for (var i = 0; i < 200 && !exited; i++) {
      if (file.existsSync()) {
        final port = int.tryParse(file.readAsLinesSync().firstOrNull ?? '');
        if (port != null) return port;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    throw StateError('engine browser did not open its DevTools port');
  }

  static Future<Map<String, Object?>> _version(int port) async {
    final client = HttpClient();
    try {
      final req = await client.get('127.0.0.1', port, '/json/version');
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      return (jsonDecode(body) as Map).cast<String, Object?>();
    } finally {
      client.close(force: true);
    }
  }

  /// Closes the browser (cookies flushed), killing it if it lingers.
  Future<void> stop() async {
    try {
      await cdp.call('Browser.close', timeout: const Duration(seconds: 3));
    } on Object {
      process.kill();
    }
    await cdp.close();
    await process.exitCode.timeout(
      const Duration(seconds: 5),
      // coverage:ignore-start
      // Only a browser that ignores SIGTERM for 5 s gets here; tests
      // cannot wait that long.
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        return -1;
      },
      // coverage:ignore-end
    );
  }
}

/// The `Cookie` header chromium would send to [url], from `Storage.
/// getCookies` entries: host-only cookies match the exact host, dotted
/// domains match subdomains too, paths match by prefix, `secure` needs
/// https, and expired ones (`expires` in seconds, -1 = session) are dropped.
String cookieHeaderFor(Uri url, List<Object?> cookies, DateTime now) {
  final host = url.host.toLowerCase();
  final path = url.path.isEmpty ? '/' : url.path;
  final out = <String>[];
  for (final c in cookies.whereType<Map<Object?, Object?>>()) {
    final domain = '${c['domain'] ?? ''}'.toLowerCase();
    final dotted = domain.startsWith('.');
    final bare = dotted ? domain.substring(1) : domain;
    final hostOk = host == bare || (dotted && host.endsWith(domain));
    final cpath = '${c['path'] ?? '/'}';
    final pathOk =
        path == cpath ||
        (path.startsWith(cpath) &&
            (cpath.endsWith('/') || path[cpath.length] == '/'));
    final secureOk = c['secure'] != true || url.scheme == 'https';
    final expires = c['expires'];
    final live =
        expires is! num ||
        expires < 0 ||
        expires * 1000 > now.millisecondsSinceEpoch;
    if (hostOk && pathOk && secureOk && live) {
      out.add('${c['name']}=${c['value']}');
    }
  }
  return out.join('; ');
}
