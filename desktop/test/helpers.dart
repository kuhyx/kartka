import 'dart:convert';
import 'dart:io';

import 'package:kartka_desktop/kartka_desktop.dart';

/// A response as the tests see it.
typedef Reply = ({int status, HttpHeaders headers, List<int> body});

/// UTF-8 body of [r].
String text(Reply r) => utf8.decode(r.body);

/// A running wrapper over temp directories.
class Harness {
  new _(this.dir, this.server);

  /// Starts a wrapper on an ephemeral port with a tiny web build.
  /// [upstream] replaces the proxy's HttpClient; [log] captures the
  /// wrapper's error log instead of stderr. [seed] (file contents) turns on
  /// the seeded-session route over a temp file; [seedFile] alone points it
  /// at a path that does not exist.
  static Future<Harness> start({
    HttpClient? upstream,
    void Function(String line)? log,
    String? seed,
    bool seedFile = false,
  }) async {
    final dir = Directory.systemTemp.createTempSync('kartka_desktop');
    final web = Directory('${dir.path}/web')..createSync();
    File('${web.path}/index.html').writeAsStringSync('<title>Kartka</title>');
    File('${web.path}/main.wasm').writeAsBytesSync([0, 97, 115, 109]);
    final seedPath = '${dir.path}/kartka-agent/firebase_auth.json';
    if (seed != null) {
      File(seedPath)
        ..createSync(recursive: true)
        ..writeAsStringSync(seed);
    }
    final server = WrapperServer(
      webRoot: web.path,
      filesDir: '${dir.path}/files',
      secretsFile: '${dir.path}/config/kartka/secrets.json',
      upstream: upstream,
      log: log,
      syncCredentialsFile: seed != null || seedFile ? seedPath : null,
    );
    await server.start(0);
    return Harness._(dir, server);
  }

  /// Temp root.
  final Directory dir;

  /// The server under test.
  final WrapperServer server;

  final _client = HttpClient();

  /// Stops everything and removes the temp directory.
  Future<void> close() async {
    _client.close(force: true);
    await server.stop();
    dir.deleteSync(recursive: true);
  }

  /// Sends [method] [path]; [api] adds `x-kartka: 1`.
  Future<Reply> call(
    String method,
    String path, {
    Map<String, String> headers = const {},
    List<int>? body,
    bool api = true,
    String? host,
  }) async {
    final request = await _client.openUrl(
      method,
      Uri.parse('http://127.0.0.1:${server.port}$path'),
    );
    request.headers.host = host ?? '127.0.0.1';
    request.headers.port = server.port;
    if (api) request.headers.set(apiHeader, '1');
    headers.forEach(request.headers.set);
    if (body != null) request.add(body);
    final response = await request.close();
    final bytes = await response.fold<List<int>>([], (a, b) => a..addAll(b));
    return (
      status: response.statusCode,
      headers: response.headers,
      body: bytes,
    );
  }
}
