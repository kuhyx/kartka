import 'dart:convert';

import 'package:crdt_sync_flutter/testing/fake_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kartka/platform/sync_access.dart';
import 'package:kartka/platform/wrapper_protocol.dart';
import 'package:kartka/sync/sync_config.dart';

final Uri _agent = Uri.parse('http://127.0.0.1:47392/#/more');

// Obviously fake values; nothing here talks to Firebase.
const _seed = {
  'id_token': 'fake-id',
  'refresh_token': 'fake-refresh',
  'expires_at': '2099-01-01T00:00:00.000Z',
  'email': 'agent@example.org',
};

/// A web access over a mock wrapper answering [status] / [body].
({SyncAccess access, List<http.Request> seen}) web(int status, [Object? body]) {
  final seen = <http.Request>[];
  final inner = MockClient((r) async {
    seen.add(r);
    return http.Response(body == null ? '' : jsonEncode(body), status);
  });
  final access = SyncAccess.of(
    kKartkaSync,
    isWeb: true,
    base: _agent,
    inner: inner,
  );
  return (access: access, seen: seen);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Android: no wrapper route, no client, the app unchanged', () {
    final access = SyncAccess.of(kKartkaSync, isWeb: false);
    expect(access.app.routes, isNull);
    expect(access.app.project, same(kKartkaSync.project));
    expect(access.client, isNull);
  });

  test('web: the wrapper route on the same project and uid', () {
    final access = web(404).access;
    expect(access.app.routes!.credentialsPath, '/sync-credentials');
    expect(
      access.app.routes!.credentialsPath,
      KartkaWrapper.syncCredentialsPath,
    );
    expect(access.app.routes!.accountPath, isNull);
    expect(access.app.project, same(kKartkaSync.project));
    expect(access.app.expectedUid, kKartkaSync.expectedUid);
  });

  test('close() keeps the shared client usable', () async {
    // crdt_sync's FirebaseRestClient.close() closes the client it was given;
    // one such call must not end sync for the whole tab.
    final inner = _ClosableClient();
    final client = WrapperApiClient(inner, Uri.parse('http://127.0.0.1:47392'))
      ..close();
    await client.get(Uri.parse('https://securetoken.googleapis.com/v1/t'));
    expect(inner.closed, isFalse);
  });

  test('web: the wrapper origin defaults to the page (Uri.base)', () {
    final access = SyncAccess.of(kKartkaSync, isWeb: true);
    final client = access.client! as WrapperApiClient;
    expect(client.origin.scheme, Uri.base.scheme);
    expect(client.origin.host, Uri.base.host);
    client.close();
  });

  test('no route on the wrapper (404): signed out, harmlessly', () async {
    installFakeSecureStorage();
    final (:access, :seen) = web(404);
    expect(await access.loadAccount(), isNull);
    expect(await access.openSync(), isNull);
    expect(
      seen.first.url,
      Uri.parse('http://127.0.0.1:47392/sync-credentials'),
    );
    expect(seen.first.headers[KartkaWrapper.apiHeader], '1');
  });

  test('a seeded session is adopted once, then read from the store', () async {
    installFakeSecureStorage();
    final (:access, :seen) = web(200, _seed);
    final account = await access.loadAccount();
    expect(account!.email, 'agent@example.org');
    expect(account.password, isEmpty);
    expect((await access.loadAccount())!.email, 'agent@example.org');
    expect(seen, hasLength(1));
  });

  test('x-kartka goes to the wrapper origin only', () async {
    final seen = <http.BaseRequest>[];
    final client = WrapperApiClient(
      MockClient((r) async {
        seen.add(r);
        return http.Response('', 200);
      }),
      Uri.parse('http://127.0.0.1:47392'),
    );
    await client.get(Uri.parse('http://127.0.0.1:47392/sync-credentials'));
    await client.get(Uri.parse('http://127.0.0.1:47391/sync-credentials'));
    await client.get(Uri.parse('https://127.0.0.1:47392/x'));
    await client.get(Uri.parse('http://localhost:47392/x'));
    await client.post(Uri.parse('https://securetoken.googleapis.com/v1/t'));
    expect(seen.map((r) => r.headers[KartkaWrapper.apiHeader]), [
      '1',
      null,
      null,
      null,
      null,
    ]);
    // Bypasses a stale browser-cached reply (a 410 Chromium keeps forever);
    // never on Firebase, where a non-safelisted header forces a preflight.
    expect(seen.map((r) => r.headers['cache-control']), [
      'no-cache',
      null,
      null,
      null,
      null,
    ]);
    client.close();
  });
}

/// Fails every request once closed, like a real client.
class _ClosableClient extends http.BaseClient {
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (closed) throw http.ClientException('closed', request.url);
    return http.StreamedResponse(const Stream.empty(), 200);
  }

  @override
  void close() => closed = true;
}
