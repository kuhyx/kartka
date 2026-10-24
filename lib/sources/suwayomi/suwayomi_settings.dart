import 'dart:async';
import 'dart:convert';

import 'package:kartka/platform/key_value_store.dart';

/// Connection settings for one Suwayomi-Server.
class SuwayomiSettings {
  /// Creates settings; an empty [serverUrl] means "not configured".
  const new({this.serverUrl = '', this.username = '', this.password = ''});

  /// Base URL, e.g. `https://manga.example.org` (no trailing slash needed).
  final String serverUrl;

  /// Basic-auth user; empty means the server runs without auth.
  final String username;

  /// Basic-auth password.
  final String password;

  /// Whether a server URL is set.
  bool get isConfigured => serverUrl.trim().isNotEmpty;

  /// The base URL without trailing slashes.
  String get base => serverUrl.trim().replaceFirst(RegExp(r'/+$'), '');

  /// The GraphQL endpoint.
  Uri get graphqlUri => Uri.parse('$base/api/graphql');

  /// Absolute URL for a server-relative [path]; absolute URLs pass through.
  String resolve(String path) {
    if (Uri.parse(path).hasScheme) return path;
    return path.startsWith('/') ? '$base$path' : '$base/$path';
  }

  /// Whether [url] points at this server (and so may carry its credentials).
  bool owns(String url) {
    if (!isConfigured) return false;
    final server = Uri.tryParse(base);
    final target = Uri.tryParse(url);
    if (server == null || target == null) return false;
    return target.scheme == server.scheme &&
        target.host == server.host &&
        target.port == server.port &&
        target.path.startsWith(server.path);
  }

  /// The `Authorization` header, or none when no username is set.
  Map<String, String> get authHeaders => username.isEmpty
      ? const {}
      : {
          'Authorization':
              'Basic ${base64.encode(utf8.encode('$username:$password'))}',
        };

  @override
  bool operator ==(Object other) =>
      other is SuwayomiSettings &&
      other.serverUrl == serverUrl &&
      other.username == username &&
      other.password == password;

  @override
  int get hashCode => Object.hash(serverUrl, username, password);
}

/// Persists [SuwayomiSettings]: the URL in plain [kv], the credentials only
/// in [secrets] (Android Keystore / wrapper file at 0600).
class SuwayomiSettingsStore {
  /// Creates a store over [kv] and [secrets].
  new({required this.kv, required this.secrets});

  /// Plain settings storage.
  final KeyValueStore kv;

  /// Secret storage for username and password.
  final KeyValueStore secrets;

  static const _urlKey = 'suwayomi.serverUrl';
  static const _userKey = 'suwayomi.username';
  static const _passKey = 'suwayomi.password';

  final _changes = StreamController<SuwayomiSettings>.broadcast();
  SuwayomiSettings? _current;

  /// The last loaded or saved settings, if any.
  SuwayomiSettings? get current => _current;

  /// Emits every saved value.
  Stream<SuwayomiSettings> get changes => _changes.stream;

  /// Reads the stored settings (empty when none are stored).
  Future<SuwayomiSettings> load() async {
    final loaded = SuwayomiSettings(
      serverUrl: await kv.get(_urlKey) ?? '',
      username: await secrets.get(_userKey) ?? '',
      password: await secrets.get(_passKey) ?? '',
    );
    return _current = loaded;
  }

  /// Stores [settings] and notifies [changes].
  Future<void> save(SuwayomiSettings settings) async {
    await kv.set(_urlKey, settings.serverUrl.trim());
    await secrets.set(_userKey, settings.username);
    await secrets.set(_passKey, settings.password);
    _changes.add(_current = settings);
  }
}
