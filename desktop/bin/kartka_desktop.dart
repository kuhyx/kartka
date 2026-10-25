// Entry point: resolves paths, binds the fixed port (or fails loudly), opens
// the browser. All serving logic lives in lib/ and is tested there.
import 'dart:io';

import 'package:kartka_desktop/kartka_desktop.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  final home = Platform.environment['HOME'];
  if (home == null) {
    stderr.writeln('HOME is not set.');
    exit(1);
  }
  final webRoot =
      _arg(args, '--web-root') ??
      p.normalize(p.join(p.dirname(Platform.resolvedExecutable), '..', 'web'));
  if (!File(p.join(webRoot, 'index.html')).existsSync()) {
    stderr.writeln('no web build at $webRoot (run: fvm flutter build web)');
    exit(1);
  }
  final server = WrapperServer(
    webRoot: webRoot,
    filesDir:
        _arg(args, '--files-dir') ??
        p.join(home, '.local', 'share', 'kartka-desktop', 'files'),
    secretsFile:
        _arg(args, '--secrets-path') ??
        p.join(home, '.config', 'kartka', 'secrets.json'),
    // Agent instance only (tools/agent): kuhy's real window never passes it
    // and keeps the Google sign-in.
    syncCredentialsFile: _arg(args, '--sync-credentials'),
    // Default: next to --files-dir, so the agent instance (its own
    // --files-dir) never shares the real app's engine profile.
    engineProfile: _arg(args, '--engine-profile'),
    // --no-browser is the headless instance: never a visible window.
    headlessOnly: args.contains('--no-browser'),
  );
  // Ctrl-C / systemd stop: take the engine's chromium down too.
  for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
    signal.watch().listen((_) async {
      await server.stop();
      exit(0);
    });
  }
  // --port is for headless verification only: the app's IndexedDB and the
  // OAuth redirect registered at AniList/MAL are keyed to kartkaPort.
  final port = int.tryParse(_arg(args, '--port') ?? '') ?? kartkaPort;
  try {
    await server.start(port);
  } on SocketException catch (e) {
    // Never fall back to another port: the OAuth redirect registered at
    // AniList/MAL and the browser's IndexedDB are both keyed to 47391.
    stderr
      ..writeln('kartka-desktop: cannot bind 127.0.0.1:$port: $e')
      ..writeln('Free the port (is Kartka already running?) and retry.');
    exit(1);
  }
  stdout.writeln('kartka-desktop serving on http://127.0.0.1:${server.port}');
  if (args.contains('--no-browser')) return;
  if (!await launchBrowser(home)) {
    stdout.writeln(
      'Browser handed off or missing; still serving. Ctrl-C stops.',
    );
    return;
  }
  await server.stop();
}

String? _arg(List<String> args, String name) {
  final i = args.indexOf(name);
  return i == -1 || i + 1 >= args.length ? null : args[i + 1];
}
