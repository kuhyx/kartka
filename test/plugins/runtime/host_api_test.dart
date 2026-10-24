import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/plugins/runtime/host_api.dart';

void main() {
  const json = <String, Object?>{
    'id': 'demo',
    'name': 'Demo',
    'version': '1.0.0',
    'lang': 'en',
    'baseUrl': 'https://demo.test',
    'apiVersion': 1,
  };

  test('manifest round-trips and derives the source id', () {
    final m = PluginManifest.fromJson({...json, 'icon': 'i.png'});
    expect(m.sourceId, 'plugin:demo');
    expect(PluginManifest.fromJson(m.toJson()).toJson(), m.toJson());
    expect(PluginManifest.fromJson(json).toJson().containsKey('icon'), false);
  });

  test('manifest rejects bad ids, fields and api versions', () {
    expect(
      () => PluginManifest.fromJson({...json, 'id': '../x'}),
      throwsFormatException,
    );
    expect(
      () => PluginManifest.fromJson({...json, 'name': 3}),
      throwsFormatException,
    );
    expect(
      () => PluginManifest.fromJson({...json, 'apiVersion': 2}),
      throwsFormatException,
    );
  });

  test('response serialises; exception names the plugin', () {
    const r = HostHttpResponse(status: 200, headers: {'a': 'b'}, body: 'x');
    expect(r.toJson(), {
      'status': 200,
      'headers': {'a': 'b'},
      'body': 'x',
    });
    const e = PluginException('demo', 'boom', method: PluginMethod.search);
    expect(e.toString(), 'Plugin "demo" search(): boom');
    expect(const PluginException('demo', 'boom').toString(), contains('demo'));
  });
}
