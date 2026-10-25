import 'dart:async';
import 'dart:io';

import 'package:kartka_desktop/src/chromium.dart';
import 'package:kartka_desktop/src/engine.dart';
import 'package:kartka_desktop/src/engine_routes.dart';
import 'package:kartka_desktop/src/oauth_routes.dart';
import 'package:kartka_desktop/src/protocol.dart';
import 'package:kartka_desktop/src/proxy.dart';
import 'package:kartka_desktop/src/seed_route.dart';
import 'package:kartka_desktop/src/static_files.dart';
import 'package:kartka_desktop/src/storage_routes.dart';
import 'package:path/path.dart' as p;

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
  /// [secretsFile]. Only with [syncCredentialsFile] (the agent instance's
  /// `--sync-credentials`) does [syncCredentialsPath] exist. The browser
  /// engine lives next to [filesDir] (`engine-profile`, `engine-hosts.json`)
  /// unless [engine] is given; [headlessOnly] (the default, and the agent
  /// instance) refuses the visible "Open in WebView" window.
  /// [allowLoopbackEngine] is for tests.
  new({
    required String webRoot,
    required String filesDir,
    required String secretsFile,
    String? syncCredentialsFile,
    HttpClient? upstream,
    void Function(String line)? log,
    EngineHost? engine,
    String? engineProfile,
    bool headlessOnly = true,
    bool allowLoopbackEngine = false,
  }) : this._(
         log ?? stderr.writeln,
         webRoot,
         filesDir,
         secretsFile,
         syncCredentialsFile,
         upstream ?? HttpClient(),
         engine ??
             ChromiumEngineHost(
               exe: findEngineBrowser(),
               profile:
                   engineProfile ??
                   p.join(p.dirname(filesDir), 'engine-profile'),
               hosts: EngineHosts(
                 p.join(p.dirname(filesDir), 'engine-hosts.json'),
               ),
               headlessOnly: headlessOnly,
               allowLoopback: allowLoopbackEngine,
             ),
         allowLoopbackEngine,
       );

  new _(
    this._log,
    String webRoot,
    String filesDir,
    String secretsFile,
    String? syncCredentialsFile,
    HttpClient upstream,
    this._engineHost,
    bool allowLoopbackEngine,
  ) : _static = StaticFiles(webRoot),
      _files = FileRoutes(filesDir),
      _secrets = SecretRoutes(secretsFile),
      _seed = syncCredentialsFile == null
          ? null
          : SeedRoute(syncCredentialsFile, _log),
      _engine = EngineRoutes(_engineHost, allowLoopback: allowLoopbackEngine),
      _proxy = ProxyRoute(upstream, _log, cookieFor: _engineHost.cookieHeader);

  final void Function(String line) _log;
  final StaticFiles _static;
  final FileRoutes _files;
  final SecretRoutes _secrets;
  final SeedRoute? _seed;
  final ProxyRoute _proxy;
  final EngineHost _engineHost;
  final EngineRoutes _engine;
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
    if (_engineHost case final ChromiumEngineHost chromium) {
      chromium.protectedPorts.add(server.port);
    }
    _oauth = OAuthRoutes(server.port);
    unawaited(server.forEach((r) => unawaited(_respond(r))));
  }

  /// Stops serving.
  Future<void> stop() async {
    await _server?.close(force: true);
    _proxy.close();
    await _engineHost.stop();
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
      path == syncCredentialsPath ||
      _under(path, enginePath) ||
      _under(path, filesPath) ||
      _under(path, secretsPath);

  static bool _under(String path, String root) =>
      path == root || path.startsWith('$root/');

  Future<void> _route(HttpRequest request) async {
    final path = request.uri.path;
    if (path == proxyPath) return await _proxy.handle(request);
    if (_under(path, filesPath)) return await _files.handle(request);
    if (_under(path, enginePath)) return await _engine.handle(request);
    if (_under(path, secretsPath)) return await _secrets.handle(request);
    // Without --sync-credentials the path falls through to a static 404.
    final seed = _seed;
    if (path == syncCredentialsPath && seed != null) {
      return seed.handle(request);
    }
    if (path == oauthPath || path == oauthResultPath) {
      return await _oauth.handle(request);
    }
    return await _static.handle(request);
  }
}

/// [text] with the query/fragment of every http(s) URL replaced by
/// `?<redacted>` / `#<redacted>` and its userinfo by `<redacted>@`.
///
/// The same rules as the app's `redactUrlQueries` (lib/core/redact.dart),
/// which this package cannot import: a query runs to whitespace, a quote or
/// `<>` (`,` and `)` are legal in it), and the query pass goes first.
/// Unlike the app, a relative query with a `=` (`/proxy?url=...`, whose
/// target is percent-encoded) is redacted too: the wrapper sees those.
String redactQueries(String text) => text
    .replaceAllMapped(_urlTail, (m) => '${m[1]}${m[2]}<redacted>')
    .replaceAllMapped(_userInfo, (m) => '${m[1]}<redacted>@')
    .replaceAll(_bareQuery, '?<redacted>');

final _urlTail = RegExp(
  r'''(https?://[^\s?#"'<>]*)([?#])[^\s"'<>]*''',
  caseSensitive: false,
);
final _userInfo = RegExp(
  r'''(https?://)[^\s/?#"'<>@]*@''',
  caseSensitive: false,
);
final _bareQuery = RegExp(r'''\?[^\s"'<>?=]*=[^\s"'<>]*''');
