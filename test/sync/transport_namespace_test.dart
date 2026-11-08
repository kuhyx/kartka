import 'dart:convert';

import 'package:crdt_sync/crdt_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kartka/platform/memory/memory_fakes.dart';
import 'package:kartka/sync/firebase_transport.dart';

/// Paths one read and one write reach, through a real crdt_sync client.
Future<List<String>> _paths({String? namespace}) async {
  final store = InMemoryCredentialStore();
  await store.save(
    FirebaseCredentials(
      idToken: 'tok',
      refreshToken: 'r',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    ),
  );
  final writes = <http.Request>[];
  final client = FirebaseRestClient(
    databaseUrl: 'https://db.example',
    auth: FirebaseTokenProvider(apiKey: 'k', store: store),
    namespace: namespace ?? '',
    httpClient: MockClient((r) async {
      writes.add(r);
      return http.Response('null', 200);
    }),
  );
  final reads = FakeKartkaHttp(
    (r) => FakeKartkaHttp.text(jsonEncode({'a': 1})),
  );
  final t = FirebaseTransport(
    writer: FirebaseRestWriter(client),
    http: reads,
    databaseUrl: 'https://db.example/',
    namespace: namespace,
  );
  await t.get('source_health/x');
  await t.get('');
  await t.patch({'revs/a': 1});
  return [
    ...reads.requests.map((r) => r.url.path),
    ...writes.map((r) => r.url.path),
  ];
}

void main() {
  test('empty namespace keeps every path byte-identical', () async {
    expect(await _paths(namespace: ''), [
      '/kartka/source_health/x.json',
      '/kartka.json',
      '/kartka.json',
    ]);
  });

  test('a sandbox namespace prefixes reads and writes alike', () async {
    expect(await _paths(namespace: 'sandbox/slot3'), [
      '/sandbox/slot3/kartka/source_health/x.json',
      '/sandbox/slot3/kartka.json',
      '/sandbox/slot3/kartka.json',
    ]);
  });

  test('an invalid namespace fails closed at construction', () {
    for (final bad in ['slot3', 'sandbox/', 'sandbox/Slot', '/x', 'a\n']) {
      expect(
        () => FirebaseTransport(
          writer: _NoWriter(),
          http: FakeKartkaHttp(),
          databaseUrl: 'https://db',
          namespace: bad,
        ),
        throwsException,
        reason: bad,
      );
    }
  });

  test('the compiled define defaults to empty (production paths)', () async {
    final reads = FakeKartkaHttp((r) => FakeKartkaHttp.text('null'));
    final t = FirebaseTransport(
      writer: _NoWriter(),
      http: reads,
      databaseUrl: 'https://db',
    );
    await t.get('revs');
    expect(reads.requests.single.url.path, '/kartka/revs.json');
  });
}

class _NoWriter implements RtdbWriter {
  @override
  Future<String> idToken() async => 'tok';

  @override
  Future<void> patchValues(String path, Map<String, Object?> values) async {}
}
