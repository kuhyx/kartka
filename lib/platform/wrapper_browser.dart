import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:kartka/platform/browser_engine.dart';
import 'package:kartka/platform/engine_core.dart';
import 'package:kartka/platform/wrapper_protocol.dart';

/// [KartkaBrowser] on the desktop wrapper's headless chromium
/// (docs/DOCS-contracts-webview.md §6). The load loop runs here, in
/// [EngineCore]; the wrapper only navigates and evaluates.
class WrapperBrowser implements KartkaBrowser {
  /// Talks to the wrapper at [base] (its origin) through [client].
  new(
    this.client,
    this.base, {
    Duration pollInterval = const Duration(milliseconds: 250),
  }) {
    _core = EngineCore(_open, pollInterval: pollInterval);
  }

  /// The (browser) client.
  final http.Client client;

  /// The wrapper's origin.
  final Uri base;

  late final EngineCore _core;

  Future<Object?> _call(String method, String path, [Object? body]) async {
    final request = http.Request(
      method,
      base.replace(path: '${KartkaWrapper.enginePath}$path'),
    )..headers[KartkaWrapper.apiHeader] = '1';
    if (body != null) {
      request
        ..headers['content-type'] = 'application/json'
        ..bodyBytes = utf8.encode(jsonEncode(body));
    }
    final res = await http.Response.fromStream(await client.send(request));
    final json = res.body.isEmpty ? null : jsonDecode(res.body);
    if (res.statusCode >= 200 && res.statusCode < 300) return json;
    final code = json is Map ? '${json['error']}' : '${res.statusCode}';
    if (res.statusCode == 503 || res.statusCode == 409) {
      throw EngineUnavailable(code);
    }
    throw StateError('engine ${res.statusCode}: $code');
  }

  Future<EnginePage> _open() async {
    final r = await _call('POST', '/page', const <String, Object?>{});
    return _WrapperPage(this, '${(r! as Map)['id']}');
  }

  @override
  Future<EngineResult> load(EngineRequest request) => _core.load(request);

  @override
  bool get inApp => false;

  @override
  Widget buildView(Uri url) => const SizedBox.shrink();

  @override
  Future<void> openExternal(Uri url) => _call('POST', '/open', {'url': '$url'});

  @override
  Future<void> finish(Uri url) => _call('POST', '/finish', {'url': '$url'});

  @override
  Widget host(Widget child) => child;
}

class _WrapperPage implements EnginePage {
  new(this.b, this.id);

  final WrapperBrowser b;
  final String id;

  @override
  Future<void> navigate(Uri url, Map<String, String> headers) => b._call(
    'POST',
    '/page/$id/navigate',
    {'url': '$url', 'headers': headers},
  );

  @override
  Future<Object?> evaluate(String js) async {
    final r = await b._call('POST', '/page/$id/evaluate', {'expression': js});
    return (r! as Map)['value'];
  }

  @override
  Future<void> close() async {
    try {
      await b._call('DELETE', '/page/$id');
    } on Object {
      return; // The wrapper closes stale pages itself.
    }
  }
}
