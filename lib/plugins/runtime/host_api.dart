/// The ONLY surface a Kartka JS plugin can reach (contracts section 6).
///
/// This file is pure Dart with no Flutter or platform imports. The Mangayomi
/// converter targets the JS names documented below; the runtime implements
/// [PluginHostServices] on the Dart side.
///
/// JS globals visible to a plugin (nothing else: no filesystem, no `fetch`,
/// no timers, no `require`):
///
/// ```text
/// kartka.http.get(url, {headers})        -> Promise<HttpResponse>
/// kartka.http.post(url, {headers, body}) -> Promise<HttpResponse>
/// kartka.html.select(html, css)          -> Promise<[{text, attrs, html}]>
/// kartka.log(...args)                    -> void
/// kartka.prefs.get(key)                  -> Promise<string | null>
/// kartka.prefs.set(key, value)           -> Promise<void>
/// HttpResponse = {status: int, headers: {string: string}, body: string}
/// ```
///
/// CLARIFICATION of section 6: every host function except `kartka.log` is
/// asynchronous (returns a Promise), because the host crosses an isolate or
/// worker boundary. `html.select` is therefore `await`ed too. Plugins must
/// declare these six global functions, each returning JSON-able values (or a
/// Promise of them) in the section 1 shapes:
///
/// ```text
/// popular(page), latest(page), search(query, page)
///     -> {items: [{url, title, coverUrl?}], hasNext: bool}
/// details(mangaUrl)
///     -> {url, title, coverUrl?, authors?: [], description?, genres?: [],
///         status?: 'ongoing'|'completed'|..., trackerIds?: {}}
/// chapters(mangaUrl)
///     -> [{url, name, number?: double, uploadedAt?: epochMs|ISO, scanlator?}]
/// pages(chapterUrl)
///     -> [{imageUrl, headers?: {}}]   // `index` is the array position
/// ```
library;

/// Version of the plugin API implemented here (`apiVersion` in manifests).
const int kPluginApiVersion = 1;

/// The six entry points a plugin must define (JS function names).
enum PluginMethod {
  /// `popular(page)`.
  popular,

  /// `latest(page)`.
  latest,

  /// `search(query, page)`.
  search,

  /// `details(mangaUrl)`.
  details,

  /// `chapters(mangaUrl)`.
  chapters,

  /// `pages(chapterUrl)`.
  pages,
}

/// Manifest `{id, name, version, lang, baseUrl, apiVersion, icon?}`.
class PluginManifest {
  /// Creates a manifest.
  const PluginManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.lang,
    required this.baseUrl,
    this.apiVersion = kPluginApiVersion,
    this.icon,
  });

  /// Parses a manifest map; throws [FormatException] when invalid.
  factory PluginManifest.fromJson(Map<String, Object?> json) {
    String req(String k) {
      final v = json[k];
      if (v is String && v.isNotEmpty) return v;
      throw FormatException('manifest field "$k" missing or not a string');
    }

    final id = req('id');
    if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(id)) {
      throw FormatException('manifest id "$id" has illegal characters');
    }
    final api = json['apiVersion'];
    if (api != kPluginApiVersion) {
      throw FormatException('unsupported apiVersion $api (want 1)');
    }
    final icon = json['icon'];
    return PluginManifest(
      id: id,
      name: req('name'),
      version: req('version'),
      lang: req('lang'),
      baseUrl: req('baseUrl'),
      icon: icon is String ? icon : null,
    );
  }

  /// Unique id; the source id becomes `plugin:<id>`.
  final String id;

  /// Display name.
  final String name;

  /// Plugin version string (compared for updates).
  final String version;

  /// Language code.
  final String lang;

  /// Site base URL.
  final String baseUrl;

  /// Plugin API version; must equal [kPluginApiVersion].
  final int apiVersion;

  /// Optional icon URL.
  final String? icon;

  /// Source id used in `SourceRef.id`.
  String get sourceId => 'plugin:$id';

  /// Serialises back to the manifest JSON shape.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'version': version,
    'lang': lang,
    'baseUrl': baseUrl,
    'apiVersion': apiVersion,
    if (icon != null) 'icon': icon,
  };
}

/// Result of `kartka.http.get/post`.
class HostHttpResponse {
  /// Creates a response.
  const HostHttpResponse({
    required this.status,
    required this.headers,
    required this.body,
  });

  /// HTTP status code.
  final int status;

  /// Response headers (lower-case names).
  final Map<String, String> headers;

  /// Body decoded as text.
  final String body;

  /// JSON handed to the plugin.
  Map<String, Object?> toJson() => {
    'status': status,
    'headers': headers,
    'body': body,
  };
}

/// One `kartka.html.select` match.
class HtmlMatch {
  /// Creates a match.
  const HtmlMatch({
    required this.text,
    required this.attrs,
    required this.html,
  });

  /// Text content.
  final String text;

  /// Element attributes.
  final Map<String, String> attrs;

  /// Outer HTML.
  final String html;

  /// JSON handed to the plugin.
  Map<String, Object?> toJson() => {'text': text, 'attrs': attrs, 'html': html};
}

/// Dart-side implementation of everything under `kartka.*`.
///
/// One instance is created per plugin so prefs and logs are scoped to it.
abstract interface class PluginHostServices {
  /// `kartka.http.get`.
  Future<HostHttpResponse> httpGet(
    String url, {
    Map<String, String> headers = const {},
  });

  /// `kartka.http.post`.
  Future<HostHttpResponse> httpPost(
    String url, {
    Map<String, String> headers = const {},
    String? body,
  });

  /// `kartka.html.select`: CSS selection over [html] (package:html).
  List<HtmlMatch> htmlSelect(String html, String css);

  /// `kartka.log`.
  void log(String message);

  /// `kartka.prefs.get`; null when unset.
  Future<String?> prefsGet(String key);

  /// `kartka.prefs.set`.
  Future<void> prefsSet(String key, String value);
}

/// Error surfaced to the UI. Always names the plugin.
class PluginException implements Exception {
  /// Creates an exception for [pluginId].
  const PluginException(this.pluginId, this.message, {this.method});

  /// Id of the failing plugin.
  final String pluginId;

  /// Human-readable cause.
  final String message;

  /// Entry point that was running, if any.
  final PluginMethod? method;

  @override
  String toString() =>
      'Plugin "$pluginId"${method == null ? '' : ' ${method!.name}()'}: '
      '$message';
}
