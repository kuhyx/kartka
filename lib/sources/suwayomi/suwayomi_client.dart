import 'dart:convert';

import 'package:kartka/platform/http_client.dart';
import 'package:kartka/sources/suwayomi/suwayomi_exceptions.dart';
import 'package:kartka/sources/suwayomi/suwayomi_queries.dart';
import 'package:kartka/sources/suwayomi/suwayomi_settings.dart';

/// Returns the settings to use for the next request.
typedef SettingsReader = SuwayomiSettings Function();

/// Minimal GraphQL-over-HTTP client for Suwayomi-Server.
///
/// Posts `{operationName, query, variables}` through [KartkaHttp] with the
/// basic-auth header and unwraps `data`, turning HTTP and GraphQL failures
/// into [SuwayomiException]s.
class SuwayomiClient {
  /// Creates a client reading fresh [settings] on every call.
  new({
    required this.http,
    required this.settings,
    this.retryDelay = const Duration(seconds: 1),
  });

  /// The app's only HTTP client.
  final KartkaHttp http;

  /// Current connection settings.
  final SettingsReader settings;

  /// Wait before the one retry of a [_retryable] failure.
  final Duration retryDelay;

  static final _operationName = RegExp(r'^\w+ (\w+)');

  /// A dropped connection, or the server's upstream WebView timing out:
  /// both usually pass on a second try.
  static final _retryable = RegExp(
    'connection abort|Connection reset|Connection closed|'
    'Timed out waiting for WebView',
    caseSensitive: false,
  );

  /// Operations that change the server: never sent twice. Every other
  /// one, `mutation` or not, only fetches (`fetchChapterPages`, ...).
  static const _changesServer = {'KartkaUpdateExtension'};

  /// Runs [document] with [variables] and returns its `data` object. A
  /// [_retryable] failure is retried once after [retryDelay] (not for an
  /// operation that changes the server).
  Future<Map<String, Object?>> run(
    String document, [
    Map<String, Object?> variables = const {},
  ]) async {
    try {
      return await _run(document, variables);
    } on Object catch (e) {
      final op = _operationName.firstMatch(document)?.group(1);
      if (_changesServer.contains(op) || !_retryable.hasMatch('$e')) rethrow;
      await Future<void>.delayed(retryDelay);
      return await _run(document, variables);
    }
  }

  Future<Map<String, Object?>> _run(
    String document,
    Map<String, Object?> variables,
  ) async {
    final current = settings();
    if (!current.isConfigured) throw const SuwayomiNotConfiguredException();
    final response = await http.post(
      current.graphqlUri,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        ...current.authHeaders,
      },
      body: jsonEncode({
        'operationName': _operationName.firstMatch(document)!.group(1),
        'query': document,
        'variables': variables,
      }),
    );
    if (response.statusCode == 401) throw const SuwayomiAuthException();
    if (!response.ok) {
      throw SuwayomiException('HTTP ${response.statusCode}');
    }
    return _data(response.body);
  }

  /// Checks URL and credentials; returns e.g. `Suwayomi-Server v2.4.2366`.
  Future<String> testConnection() async {
    final data = await run(SuwayomiQueries.about);
    final about = data['aboutServer']! as Map<String, Object?>;
    return '${about['name']} ${about['version']}';
  }

  static Map<String, Object?> _data(String body) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw const SuwayomiException('not a GraphQL response');
    }
    if (decoded is! Map<String, Object?>) {
      throw const SuwayomiException('not a GraphQL response');
    }
    final errors = decoded['errors'];
    if (errors is List && errors.isNotEmpty) {
      final first = errors.first;
      final message = first is Map ? '${first['message']}' : '$first';
      throw SuwayomiException(message.split(RegExp(r'[\r\n]')).first);
    }
    final data = decoded['data'];
    if (data is! Map<String, Object?>) {
      throw const SuwayomiException('response has no data');
    }
    return data;
  }
}
