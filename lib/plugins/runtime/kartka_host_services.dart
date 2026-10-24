import 'package:kartka/platform/http_client.dart';
import 'package:kartka/plugins/runtime/host_api.dart';
import 'package:kartka/plugins/runtime/html_select.dart';
import 'package:kartka/plugins/runtime/plugin_index.dart';
import 'package:kartka/plugins/runtime/plugin_store.dart';

/// [PluginHostServices] for one installed plugin: HTTP only through
/// [KartkaHttp], HTML through package:html, prefs scoped to the plugin id.
class KartkaHostServices implements PluginHostServices {
  /// Creates the services for plugin [pluginId].
  const new({
    required this.pluginId,
    required this.http,
    required this.store,
    this.onLog,
  });

  /// Owner of the prefs namespace.
  final String pluginId;

  /// The only network path.
  final KartkaHttp http;

  /// Prefs live here.
  final PluginStore store;

  /// Receives `kartka.log` lines (default: dropped).
  final void Function(String pluginId, String message)? onLog;

  Uri _checked(String url) {
    final u = Uri.tryParse(url);
    if (u == null || !isHttpUrl(u)) {
      throw ArgumentError('only http(s) URLs are allowed: $url');
    }
    return u;
  }

  HostHttpResponse _wrap(KartkaResponse r) =>
      HostHttpResponse(status: r.statusCode, headers: r.headers, body: r.body);

  @override
  Future<HostHttpResponse> httpGet(
    String url, {
    Map<String, String> headers = const {},
  }) async => _wrap(await http.get(_checked(url), headers: headers));

  @override
  Future<HostHttpResponse> httpPost(
    String url, {
    Map<String, String> headers = const {},
    String? body,
  }) async =>
      _wrap(await http.post(_checked(url), headers: headers, body: body));

  @override
  List<HtmlMatch> htmlSelect(String html, String css) => selectHtml(html, css);

  @override
  void log(String message) => onLog?.call(pluginId, message);

  @override
  Future<String?> prefsGet(String key) => store.prefGet(pluginId, key);

  @override
  Future<void> prefsSet(String key, String value) =>
      store.prefSet(pluginId, key, value);
}
