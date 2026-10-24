import 'dart:async';
import 'dart:io';

import 'package:kartka_desktop/src/oauth_routes.dart';
import 'package:kartka_desktop/src/protocol.dart';
import 'package:kartka_desktop/src/proxy.dart';
import 'package:kartka_desktop/src/static_files.dart';
import 'package:kartka_desktop/src/storage_routes.dart';

/// The local server behind the desktop app.
///
/// Binds 127.0.0.1 only, and on top of that refuses (each tested):
/// * a `Host` other than `127.0.0.1:<port>` / `localhost:<port>` (DNS
///   rebinding: a hostile name resolving to 127.0.0.1 still sends its own
///   Host);
/// * a non-GET/HEAD request whose `Origin` is another site;
/// * an API call without the `x-kartka: 1` header (cross-site pages cannot
///   add it without a preflight, and no route answers OPTIONS);
/// and never emits `Access-Control-Allow-Origin`.
class WrapperServer {
  /// Serves [webRoot]; stores blobs under [filesDir] and secrets in
  /// [secretsFile].
  new({
    required String webRoot,
    required String filesDir,
    required String secretsFile,
    HttpClient? upstream,
    void Function(String line)? log,
  }) : this._(
         log ?? stderr.writeln,
         webRoot,
         filesDir,
         secretsFile,
         upstream ?? HttpClient(),
       );

  new _(
    this._log,
    String webRoot,
    String filesDir,
    String secretsFile,
    HttpClient upstream,
  ) : _static = StaticFiles(webRoot),
      _files = FileRoutes(filesDir),
      _secrets = SecretRoutes(secretsFile),
      _proxy = ProxyRoute(upstream, _log);

  final void Function(String line) _log;
  final StaticFiles _static;
  final FileRoutes _files;
  final SecretRoutes _secrets;
  final ProxyRoute _proxy;
  late OAuthRoutes _oauth;
  HttpServer? _server;

  /// Bound port (after [start]).
  int get port => _server!.port;

  /// Binds loopback [requestedPort] (0 = any, for tests). Throws
  /// [SocketException] when the port is taken: the caller must fail loudly,
  /// never move (the OAuth redirect and the browser data are port-keyed).
  Future<void> start([int requestedPort = kartkaPort]) async {
    final server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      requestedPort,
    );
    _server = server;
    _oauth = OAuthRoutes(server.port);
    unawaited(server.forEach((r) => unawaited(_respond(r))));
  }

  /// Stops serving.
  Future<void> stop() async {
    await _server?.close(force: true);
    _proxy.close();
  }

  Future<void> _respond(HttpRequest request) async {
    final response = request.response;
    response.headers.set('x-content-type-options', 'nosniff');
    try {
      final refusal = _refusal(request);
      if (refusal != null) {
        await request.drain<void>();
        response.statusCode = refusal;
      } else {
        await _route(request);
      }
    } on Object catch (e) {
      // Path only, and queries scrubbed from the error: a /proxy target can
      // carry a credential (RTDB `?auth=<token>`), and HttpException
      // embeds the full upstream URI in its message.
      _log('kartka-desktop: ${request.uri.path}: ${redactQueries('$e')}');
      response.statusCode = HttpStatus.internalServerError;
    }
    await response.close();
  }

  int? _refusal(HttpRequest request) {
    final host = request.headers.value('host');
    if (host != '127.0.0.1:$port' && host != 'localhost:$port') {
      return HttpStatus.misdirectedRequest;
    }
    final origin = request.headers.value('origin');
    final safe = request.method == 'GET' || request.method == 'HEAD';
    if (!safe &&
        origin != null &&
        origin != 'http://127.0.0.1:$port' &&
        origin != 'http://localhost:$port') {
      return HttpStatus.forbidden;
    }
    if (_isApi(request.uri.path) && request.headers.value(apiHeader) != '1') {
      return HttpStatus.forbidden;
    }
    return null;
  }

  static bool _isApi(String path) =>
      path == proxyPath ||
      path == oauthResultPath ||
      _under(path, filesPath) ||
      _under(path, secretsPath);

  static bool _under(String path, String root) =>
      path == root || path.startsWith('$root/');

  Future<void> _route(HttpRequest request) async {
    final path = request.uri.path;
    if (path == proxyPath) return await _proxy.handle(request);
    if (_under(path, filesPath)) return await _files.handle(request);
    if (_under(path, secretsPath)) return await _secrets.handle(request);
    if (path == oauthPath || path == oauthResultPath) {
      return await _oauth.handle(request);
    }
    return await _static.handle(request);
  }
}

/// [text] with every URL query (`?...` up to whitespace, `,` or `)`)
/// replaced by `?<redacted>`.
String redactQueries(String text) =>
    text.replaceAll(RegExp(r'\?[^\s,)]*'), '?<redacted>');
