import 'package:kartka/plugins/runtime/host_api.dart';

/// One source listed in a Mangayomi repo `index.json`.
///
/// Only the fields Kartka uses are typed; [raw] keeps the whole entry because
/// the extension reads it back as `this.source` (for example `apiUrl`,
/// `lang`, `dateFormat`).
class MangayomiEntry {
  /// Creates an entry.
  const MangayomiEntry({
    required this.id,
    required this.name,
    required this.lang,
    required this.baseUrl,
    required this.version,
    required this.sourceCodeUrl,
    required this.raw,
    this.apiUrl = '',
    this.iconUrl,
    this.isNsfw = false,
    this.hasCloudflare = false,
  });

  /// Parses one index entry; throws [FormatException] when a required field
  /// is missing.
  factory MangayomiEntry.fromJson(Map<String, Object?> json) {
    String req(String key) {
      final v = json[key];
      if (v is String && v.isNotEmpty) return v;
      throw FormatException('Mangayomi entry field "$key" missing');
    }

    final id = json['id'];
    if (id is! int) {
      throw const FormatException('Mangayomi entry field "id" missing');
    }
    final apiUrl = json['apiUrl'];
    final icon = json['iconUrl'];
    return MangayomiEntry(
      id: id,
      name: req('name'),
      lang: req('lang'),
      baseUrl: req('baseUrl'),
      version: req('version'),
      sourceCodeUrl: req('sourceCodeUrl'),
      apiUrl: apiUrl is String ? apiUrl : '',
      iconUrl: icon is String && icon.isNotEmpty ? icon : null,
      isNsfw: json['isNsfw'] == true,
      hasCloudflare: json['hasCloudflare'] == true,
      raw: Map.unmodifiable(json),
    );
  }

  /// True when [json] is a JS manga source Kartka can convert: JavaScript
  /// (`sourceCodeLanguage` 1, Dart is 0), manga (`itemType` 0; 1 is anime,
  /// 2 novel) and with a `.js` source file.
  static bool isConvertible(Map<String, Object?> json) {
    final url = json['sourceCodeUrl'];
    return json['sourceCodeLanguage'] == 1 &&
        (json['itemType'] ?? 0) == 0 &&
        url is String &&
        Uri.tryParse(url)?.path.endsWith('.js') == true;
  }

  /// Mangayomi's numeric source id (one per language variant).
  final int id;

  /// Display name.
  final String name;

  /// Language code, e.g. `en` or `all`.
  final String lang;

  /// Site URL.
  final String baseUrl;

  /// API URL used by some extensions; empty when unused.
  final String apiUrl;

  /// Extension version.
  final String version;

  /// URL of the extension's JS file.
  final String sourceCodeUrl;

  /// Icon URL, if any.
  final String? iconUrl;

  /// Marked adult content by the repo.
  final bool isNsfw;

  /// The repo says the site sits behind Cloudflare (Kartka does not bypass
  /// challenges; such sources usually fail).
  final bool hasCloudflare;

  /// The whole index entry, handed to the extension as `this.source`.
  final Map<String, Object?> raw;

  /// Kartka plugin id: `mangayomi-<id>`.
  String get pluginId => 'mangayomi-$id';

  /// Manifest of the converted plugin (contracts §6).
  PluginManifest toManifest() => PluginManifest(
    id: pluginId,
    name: name,
    version: version,
    lang: lang,
    baseUrl: baseUrl,
    icon: iconUrl,
  );
}
