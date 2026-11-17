import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kartka/platform/agent_probe.dart';
import 'package:kartka/platform/wrapper_protocol.dart';

void main() {
  final base = Uri.parse('http://127.0.0.1:47392/#/library');

  Future<bool> probe(MockClientHandler answer, {bool isWeb = true}) =>
      isAgentInstance(isWeb: isWeb, base: base, client: MockClient(answer));

  test('asks the wrapper, with the API header', () async {
    late http.Request seen;
    expect(
      await probe((r) async {
        seen = r;
        return http.Response('{"agent":true}', 200);
      }),
      isTrue,
    );
    expect(
      seen.url,
      Uri.parse('http://127.0.0.1:47392${KartkaWrapper.agentPath}'),
    );
    expect(seen.headers[KartkaWrapper.apiHeader], '1');
  });

  test('anything but an explicit yes is no', () async {
    expect(
      await probe((_) async => http.Response('{"agent":false}', 200)),
      isFalse,
    );
    // An older wrapper serves index.html for the path.
    expect(await probe((_) async => http.Response('<html>', 200)), isFalse);
    expect(await probe((_) async => throw Exception('down')), isFalse);
    expect(
      await probe((_) async => fail('Android never asks'), isWeb: false),
      isFalse,
    );
  });
}
