import 'dart:io';

import 'package:kartka_desktop/src/protocol.dart';
import 'package:path/path.dart' as p;

/// Browser profile for the app window. Fixed: IndexedDB (the app's data)
/// lives in it, keyed by origin, so moving it hides the user's library.
String profileDir(String home) =>
    p.join(home, '.local', 'share', 'kartka-desktop', 'profile');

/// The URL the window opens. `127.0.0.1`, not `localhost`: the OAuth
/// redirect registered at AniList/MAL is `http://127.0.0.1:8791/oauth`, and
/// the result page must share the app's origin.
const appUrl = 'http://127.0.0.1:$kartkaPort';

/// First Chrome-family browser found, or `''`. [override] defaults to
/// `$KARTKA_BROWSER`.
String findBrowser({String? override, bool Function(String path)? exists}) {
  final candidates = [
    override ?? Platform.environment['KARTKA_BROWSER'] ?? '',
    '/opt/google/chrome/chrome',
    '/opt/thorium-browser/thorium-browser',
    '/usr/bin/google-chrome-stable',
    '/usr/bin/chromium',
    '/usr/bin/brave',
  ];
  final test = exists ?? (String path) => File(path).existsSync();
  return candidates.firstWhere(
    (path) => path.isNotEmpty && test(path),
    orElse: () => '',
  );
}

/// Chrome arguments for the app window.
List<String> browserArgs(String home) => [
  '--app=$appUrl',
  '--user-data-dir=${profileDir(home)}',
  // WM_CLASS, matched by the .desktop StartupWMClass.
  '--class=kartka',
  '--no-first-run',
  // A locked GNOME keyring blocks page loads behind an unlock prompt.
  '--password-store=basic',
  // Drops command-line extensions from chromium-flags.conf.
  '--disable-extensions',
];

/// Opens the app window; returns whether the browser ran long enough to
/// have owned the session (a quick exit means it handed the URL to an
/// already running instance, so the server must keep serving).
Future<bool> launchBrowser(
  String home, {
  String? browser,
  Future<Process> Function(String exe, List<String> args)? start,
}) async {
  final exe = browser ?? findBrowser();
  if (exe.isEmpty) {
    stderr.writeln('No Chrome-family browser found; open $appUrl manually.');
    return false;
  }
  final began = DateTime.now();
  final process = await (start ?? Process.start)(exe, browserArgs(home));
  await process.exitCode;
  return DateTime.now().difference(began) > const Duration(seconds: 5);
}
