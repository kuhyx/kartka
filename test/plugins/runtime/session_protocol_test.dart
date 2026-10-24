import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/plugins/runtime/engine.dart';
import 'package:kartka/plugins/runtime/engine_default.dart';
import 'package:kartka/plugins/runtime/engine_quickjs.dart';
import 'package:kartka/plugins/runtime/host_api.dart';
import 'package:kartka/plugins/runtime/plugin_session.dart';

import 'support.dart';

/// Engine that plays back a script of JS-to-Dart messages per call.
class ScriptedEngine implements JsEngine {
  new(this.onCall);
  final void Function(Map<String, Object?> call, EngineMessageSink send) onCall;
  late EngineMessageSink sink;
  final List<String> posted = [];
  bool disposed = false;

  @override
  Future<void> start(String pluginSource, EngineMessageSink onMessage) async =>
      sink = onMessage;

  @override
  void post(String json) {
    posted.add(json);
    final m = jsonDecode(json) as Map<String, Object?>;
    if (m['t'] == 'call') onCall(m, sink);
  }

  @override
  Future<void> dispose() async => disposed = true;
}

void main() {
  const manifest = PluginManifest(
    id: 'fake',
    name: 'Fake',
    version: '1',
    lang: 'en',
    baseUrl: 'https://f.test',
  );

  PluginSession make(ScriptedEngine e) => PluginSession(
    manifest: manifest,
    source: '',
    services: FakeServices(),
    engineFactory: () => e,
  );

  test('garbage and unknown messages from the sandbox are ignored', () async {
    final e = ScriptedEngine((call, send) {
      send('not json');
      send(jsonEncode({'t': 'weird'}));
      send(jsonEncode({'t': 'result', 'id': 999, 'ok': true}));
      send(
        jsonEncode({
          't': 'host',
          'op': 'log',
          'args': ['hi'],
        }),
      );
      send(
        jsonEncode({'t': 'result', 'id': call['id'], 'ok': true, 'value': 7}),
      );
      send(
        jsonEncode({'t': 'result', 'id': call['id'], 'ok': true, 'value': 8}),
      );
    });
    final s = make(e);
    expect(await s.call(PluginMethod.popular, [1]), 7);
    await s.dispose();
    expect(e.disposed, true);
  });

  test('a host call on a killed engine gets no reply', () async {
    final services = FakeServices()..delay = const Duration(milliseconds: 100);
    late ScriptedEngine e;
    e = ScriptedEngine((call, send) {
      send(
        jsonEncode({
          't': 'host',
          'id': 1,
          'op': 'http.get',
          'args': ['https://demo.test/m/1'],
        }),
      );
    });
    final s = PluginSession(
      manifest: manifest,
      source: '',
      services: services,
      engineFactory: () => e,
    );
    await expectLater(
      s.call(PluginMethod.popular, [
        1,
      ], timeout: const Duration(milliseconds: 20)),
      throwsA(isA<PluginException>()),
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(e.posted.where((p) => p.contains('"reply"')), isEmpty);
  });

  test('host replies that throw come back as ok:false', () async {
    final e = ScriptedEngine((call, send) {
      send(
        jsonEncode({'t': 'host', 'id': 5, 'op': 'nope', 'args': <Object?>[]}),
      );
    });
    final s = make(e);
    unawaited(
      s
          .call(PluginMethod.popular, [
            1,
          ], timeout: const Duration(milliseconds: 50))
          .catchError((_) => null),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final reply = e.posted
        .map((p) => jsonDecode(p) as Map)
        .firstWhere((m) => m['t'] == 'reply');
    expect(reply['ok'], false);
    expect(reply['error'], contains('unknown host operation'));
    await Future<void>.delayed(const Duration(milliseconds: 80));
  });

  test('an engine that throws on post fails the call with the id', () async {
    final e = ScriptedEngine((call, send) => throw StateError('vm died'));
    await expectLater(
      make(e).call(PluginMethod.popular, [1]),
      throwsA(
        isA<PluginException>().having(
          (x) => x.message,
          'm',
          contains('vm died'),
        ),
      ),
    );
  });

  test('platform engine selection', () {
    expect(createDefaultEngine(), isA<QuickJsEngine>());
  });
}
