import 'package:kartka/plugins/runtime/host_api.dart';

/// Browser-safe host services for the worker test (no dart:io).
class WebServices implements PluginHostServices {
  final Map<String, String> prefs = {};

  @override
  Future<HostHttpResponse> httpGet(
    String url, {
    Map<String, String> headers = const {},
  }) async => const HostHttpResponse(
    status: 200,
    headers: {},
    body: '<ul><li><a href="/a">A</a></li></ul>',
  );

  @override
  Future<HostHttpResponse> httpPost(
    String url, {
    Map<String, String> headers = const {},
    String? body,
  }) => httpGet(url);

  @override
  void log(String message) {}

  @override
  Future<String?> prefsGet(String key) async => prefs[key];

  @override
  Future<void> prefsSet(String key, String value) async => prefs[key] = value;

  @override
  Future<Map<String, Object?>> browserLoad(
    String url, {
    Map<String, String> headers = const {},
    List<String> scripts = const [],
    String? waitFor,
    bool awaitResponse = false,
    int? timeoutMs,
  }) async => throw UnsupportedError('no browser in these tests');
}
