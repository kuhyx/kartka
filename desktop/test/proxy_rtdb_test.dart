import 'dart:convert';
import 'dart:io';

import 'package:kartka_desktop/src/server.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// The exact read the web build's sync makes through /proxy.
const _token = 'eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiJrdWh5In0.c2lnLV9hYmMtMTIz_X-y';
const _rtdb =
    'https://kuhy-syncs-default-rtdb.europe-west1.firebasedatabase.app'
    '/kartka/revs.json?auth=$_token';

/// What reached the fake RTDB: the raw request line target and the Host.
typedef Seen = ({String target, String? host});

/// A plain-TCP stand-in for RTDB. The proxy's HttpClient is pointed at it
/// by a connection factory, so the real `https://…firebasedatabase.app`
/// URL goes through the proxy unchanged and no live network is touched.
/// [cut] answers with a truncated body, then drops the connection.
Future<(ServerSocket, List<Seen>)> _fakeRtdb({bool cut = false}) async {
  final seen = <Seen>[];
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((socket) {
    final buf = StringBuffer();
    socket.listen((chunk) async {
      buf.write(latin1.decode(chunk));
      final head = buf.toString();
      if (!head.contains('\r\n\r\n')) return;
      final lines = head.split('\r\n');
      final host = lines
          .firstWhere((l) => l.toLowerCase().startsWith('host:'))
          .substring(5)
          .trim();
      seen.add((target: lines.first.split(' ')[1], host: host));
      final body = cut ? '{"pc":"4' : '{"pc":"41"}';
      final length = cut ? 100 : body.length;
      socket.write(
        'HTTP/1.1 200 OK\r\ncontent-type: application/json\r\n'
        'content-length: $length\r\n\r\n$body',
      );
      await socket.flush();
      cut ? socket.destroy() : await socket.close();
    });
  });
  return (server, seen);
}

HttpClient _pointedAt(ServerSocket fake) =>
    HttpClient()
      ..connectionFactory = (uri, proxyHost, proxyPort) =>
          Socket.startConnect(InternetAddress.loopbackIPv4, fake.port);

/// The /proxy request exactly as ProxyKartkaHttp builds it.
String _proxied(String url) =>
    Uri(path: '/proxy', queryParameters: {'url': url}).toString();

void main() {
  test(
    'RTDB read: path and auth query reach upstream byte-identical',
    () async {
      final (fake, seen) = await _fakeRtdb();
      final logs = <String>[];
      final h = await Harness.start(upstream: _pointedAt(fake), log: logs.add);
      addTearDown(() async {
        await h.close();
        await fake.close();
      });
      final r = await h.call('GET', _proxied(_rtdb));
      expect((r.status, text(r)), (200, '{"pc":"41"}'));
      expect(seen, hasLength(1));
      expect(seen.single.target, '/kartka/revs.json?auth=$_token');
      expect(
        seen.single.host,
        'kuhy-syncs-default-rtdb.europe-west1.firebasedatabase.app',
      );
      expect(logs, isEmpty);
    },
  );

  test('an upstream cut mid-body never logs the token, and the wrapper '
      'keeps serving', () async {
    final (fake, _) = await _fakeRtdb(cut: true);
    final logs = <String>[];
    final h = await Harness.start(upstream: _pointedAt(fake), log: logs.add);
    addTearDown(() async {
      await h.close();
      await fake.close();
    });
    await h.call('GET', _proxied(_rtdb)).then<void>((_) {}, onError: (_) {});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(logs, isNotEmpty, reason: 'the failure path was exercised');
    expect(logs.join('\n'), isNot(contains(_token)));
    expect(logs.join('\n'), isNot(contains('auth=')));
    expect((await h.call('GET', '/')).status, 200);
  });

  test('redactQueries scrubs every query, keeps the rest', () {
    expect(
      redactQueries('x, uri = https://h/p?auth=t&a=b, y (http://h/?k=v)'),
      'x, uri = https://h/p?<redacted>, y (http://h/?<redacted>)',
    );
    expect(redactQueries('no query'), 'no query');
  });
}
