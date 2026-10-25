import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:kartka_desktop/src/cdp.dart';
import 'package:test/test.dart';

/// A fake DevTools endpoint: answers by method name, and records sessions.
Future<HttpServer> fakeDevTools(List<Map<String, Object?>> seen) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((r) async {
    final ws = await WebSocketTransformer.upgrade(r);
    ws.listen((data) {
      final m = (jsonDecode('$data') as Map).cast<String, Object?>();
      seen.add(m);
      switch (m['method']) {
        case 'Ok':
          ws
            ..add('not json')
            ..add('[1]')
            ..add(jsonEncode({'method': 'Some.event'}))
            ..add(
              jsonEncode({
                'id': m['id'],
                'result': {'a': 1},
              }),
            );
        case 'NoResult':
          ws.add(jsonEncode({'id': m['id']}));
        case 'Fails':
          ws.add(
            jsonEncode({
              'id': m['id'],
              'error': {'message': 'nope'},
            }),
          );
        case 'Hang':
          break;
        case 'Bye':
          unawaited(ws.close());
      }
    });
  });
  return server;
}

void main() {
  test('calls, errors, events, timeouts and a lost connection', () async {
    final seen = <Map<String, Object?>>[];
    final server = await fakeDevTools(seen);
    addTearDown(() => server.close(force: true));
    final cdp = await CdpClient.connect(
      Uri.parse('ws://127.0.0.1:${server.port}/devtools/browser/x'),
    );
    expect(await cdp.call('Ok', params: {'p': 1}, sessionId: 's1'), {'a': 1});
    expect(seen.single['sessionId'], 's1');
    expect(await cdp.call('NoResult'), isEmpty);
    expect(seen.last.containsKey('sessionId'), isFalse);
    await expectLater(
      cdp.call('Fails'),
      throwsA(
        isA<CdpException>().having(
          (e) => '$e',
          'text',
          'CdpException(Fails: nope)',
        ),
      ),
    );
    await expectLater(
      cdp.call('Hang', timeout: const Duration(milliseconds: 50)),
      throwsA(isA<CdpException>().having((e) => e.message, 'msg', 'timed out')),
    );
    final pending = expectLater(cdp.call('Hang'), throwsA(isA<CdpException>()));
    await expectLater(cdp.call('Bye'), throwsA(isA<CdpException>()));
    await pending;
    expect(cdp.isClosed, isTrue);
    await expectLater(
      cdp.call('Ok'),
      throwsA(isA<CdpException>().having((e) => e.method, 'method', 'Ok')),
    );
    await cdp.close();
  });
}
