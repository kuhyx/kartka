import 'package:kartka/platform/browser_engine.dart';
import 'package:kartka/platform/challenge_detect.dart';
import 'package:kartka/platform/engine_core.dart';
import 'package:kartka/platform/http_client.dart';
import 'package:kartka/plugins/runtime/host_api.dart';
import 'package:kartka/plugins/runtime/plugin_index.dart';
import 'package:kartka/plugins/runtime/plugin_store.dart';

/// [PluginHostServices] for one installed plugin: HTTP only through
/// [KartkaHttp], prefs scoped to the plugin id.
class KartkaHostServices implements PluginHostServices {
  /// Creates the services for plugin [pluginId].
  const new({
    required this.pluginId,
    required this.http,
    required this.store,
    this.onLog,
    this.browser = const UnavailableBrowser(),
  });

  /// Owner of the prefs namespace.
  final String pluginId;

  /// The only network path.
  final KartkaHttp http;

  /// Prefs live here.
  final PluginStore store;

  /// The engine behind `kartka.browser.load`.
  final KartkaBrowser browser;

  /// Receives `kartka.log` lines (default: dropped).
  final void Function(String pluginId, String message)? onLog;

  Uri _checked(String url) {
    final u = Uri.tryParse(url);
    if (u == null || !isHttpUrl(u)) {
      throw ArgumentError('only http(s) URLs are allowed: $url');
    }
    return u;
  }

  /// Throws [ChallengeRequired] on an interstitial (contract §2): the
  /// plugin must not parse a challenge page as content.
  HostHttpResponse _wrap(Uri url, KartkaResponse r) {
    final kind = challengeKindOf(r);
    if (kind != null) throw ChallengeRequired(url, kind);
    return HostHttpResponse(
      status: r.statusCode,
      headers: r.headers,
      body: r.body,
    );
  }

  @override
  Future<HostHttpResponse> httpGet(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    final u = _checked(url);
    return _wrap(u, await http.get(u, headers: headers));
  }

  @override
  Future<HostHttpResponse> httpPost(
    String url, {
    Map<String, String> headers = const {},
    String? body,
  }) async {
    final u = _checked(url);
    return _wrap(u, await http.post(u, headers: headers, body: body));
  }

  @override
  Future<Map<String, Object?>> browserLoad(
    String url, {
    Map<String, String> headers = const {},
    List<String> scripts = const [],
    String? waitFor,
    bool awaitResponse = false,
    int? timeoutMs,
  }) async {
    final u = Uri.tryParse(url);
    if (u == null || !isEngineUrlAllowed(u)) {
      throw ArgumentError('URL not allowed in the browser engine: $url');
    }
    final result = await browser.load(
      EngineRequest(
        url: u,
        headers: headers,
        scripts: scripts,
        waitFor: waitFor,
        awaitResponse: awaitResponse,
        timeout: timeoutMs == null
            ? EngineRequest.defaultTimeout
            : Duration(milliseconds: timeoutMs),
      ),
    );
    return result.toJson();
  }

  @override
  void log(String message) => onLog?.call(pluginId, message);

  @override
  Future<String?> prefsGet(String key) => store.prefGet(pluginId, key);

  @override
  Future<void> prefsSet(String key, String value) =>
      store.prefSet(pluginId, key, value);
}
