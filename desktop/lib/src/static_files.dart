import 'dart:io';

import 'package:path/path.dart' as p;

/// Serves the Flutter web build.
class StaticFiles {
  /// Serves files under [root].
  new(this.root);

  /// The `build/web` directory.
  final String root;

  /// Answers GET/HEAD for a file under [root]; 404 otherwise.
  Future<void> handle(HttpRequest request) async {
    final response = request.response;
    if (request.method != 'GET' && request.method != 'HEAD') {
      response.statusCode = HttpStatus.methodNotAllowed;
      return;
    }
    final path = request.uri.path;
    final relative = path == '/' ? 'index.html' : path.substring(1);
    final resolved = p.normalize(p.join(root, relative));
    // Dart's HttpServer already collapses `..` (so this is unreachable, see
    // server_test); kept so the guarantee does not depend on that.
    // coverage:ignore-start
    if (!p.isWithin(root, resolved)) {
      response.statusCode = HttpStatus.notFound;
      return;
    }
    // coverage:ignore-end
    final file = File(resolved);
    if (!file.existsSync()) {
      response.statusCode = HttpStatus.notFound;
      return;
    }
    response.headers
      ..contentType = contentTypeFor(resolved)
      // The shell must revalidate so a rebuilt app is picked up.
      ..set('cache-control', 'no-cache');
    if (request.method == 'GET') await response.addStream(file.openRead());
  }
}

/// Content type for [path]. CanvasKit refuses a `.wasm` served as anything
/// but `application/wasm`, and a mislabelled `.js` renders nothing.
ContentType contentTypeFor(String path) =>
    switch (p.extension(path).toLowerCase()) {
      '.html' => ContentType.html,
      '.js' || '.mjs' => ContentType('text', 'javascript', charset: 'utf-8'),
      '.json' => ContentType.json,
      '.wasm' => ContentType('application', 'wasm'),
      '.css' => ContentType('text', 'css', charset: 'utf-8'),
      '.png' => ContentType('image', 'png'),
      '.jpg' || '.jpeg' => ContentType('image', 'jpeg'),
      '.svg' => ContentType('image', 'svg+xml'),
      '.ico' => ContentType('image', 'x-icon'),
      '.ttf' => ContentType('font', 'ttf'),
      '.otf' => ContentType('font', 'otf'),
      '.woff2' => ContentType('font', 'woff2'),
      _ => ContentType.binary,
    };
