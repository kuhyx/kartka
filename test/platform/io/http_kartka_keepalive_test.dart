import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';
import 'package:kartka/platform/http_kartka.dart';

/// The real dart:io stack, not a mock: a server that closes a pooled
/// keep-alive connection when it is reused gives exactly reader.open's
/// "Connection closed before full header was received" (0ba7b071).
void main() {
  test('a reused connection the server dropped is sent again', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final seen = <HttpConnectionInfo?>[];
    server.listen((request) async {
      final reused = seen.any(
        (c) => c?.remotePort == request.connectionInfo?.remotePort,
      );
      seen.add(request.connectionInfo);
      if (reused) {
        // The server timed the idle link out just as the client reused it.
        final socket = await request.response.detachSocket(writeHeaders: false);
        socket.destroy();
        return;
      }
      request.response
        ..persistentConnection = true
        ..write('ok');
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));
    final http = DirectKartkaHttp(IOClient(HttpClient()));
    final url = Uri.parse('http://127.0.0.1:${server.port}/');

    expect((await http.get(url)).body, 'ok');
    final again = await http.get(url);

    expect(again.statusCode, 200);
    expect(again.body, 'ok');
    expect(seen, hasLength(3)); // dropped once, then a fresh connection
  });
}
