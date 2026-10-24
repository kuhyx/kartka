import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/app/feature.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:kartka/platform/platform.dart';
import 'package:kartka/tracking/common/tracker.dart';
import 'package:kartka/tracking/mal/mal_feature.dart';
import 'package:kartka/tracking/mal/mal_http.dart';
import 'package:kartka/tracking/mal/mal_tokens.dart';
import 'package:kartka/tracking/mal/mal_transport.dart';

import 'mal_fakes.dart';

void main() {
  late FakeKartkaHttp http;
  late MemoryKeyValueStore secrets;
  late MemoryKeyValueStore kv;
  late KartkaEnv env;
  var status = 200;
  var body = '{}';

  setUp(() {
    status = 200;
    body = '{}';
    http = FakeKartkaHttp((_) => FakeKartkaHttp.text(body, status: status));
    secrets = MemoryKeyValueStore();
    kv = MemoryKeyValueStore();
    env = KartkaEnv(
      memoryPlatform(
        http: http,
        kv: kv,
        secrets: secrets,
        oauth: FakeOAuthRedirect(
          (a) => Uri.parse(
            'kartka://oauth?code=c&state=${a.queryParameters['state']}',
          ),
        ),
      ),
    );
  });

  test('adapter forwards method, headers and body', () async {
    status = 201;
    body = 'ok';
    final res = await malSendVia(http)(
      MalRequest(
        MalMethod.patch,
        Uri.parse('https://x.test/a'),
        headers: const {'H': 'v'},
        body: 'b=1',
      ),
    );
    expect(res.statusCode, 201);
    expect(res.body, 'ok');
    expect(http.requests.single.method, 'PATCH');
    expect(http.requests.single.headers, {'H': 'v'});
    expect(http.requests.single.body, 'b=1');
  });

  test('every MalMethod is a method KartkaHttp allows', () {
    for (final m in MalMethod.values) {
      expect(KartkaHttp.methods, contains(malMethodName(m)));
    }
  });

  test('no client id built in: no tracker', () {
    final feature = malFeature(env, clientId: '');
    expect(feature.id, 'tracking-mal');
    expect(feature.services, isEmpty);
  });

  test('default factory reads the build-time id (empty in tests)', () {
    expect(malFeature(env).services, isEmpty);
    expect(malFeature(env, isWeb: true).services, isEmpty);
  });

  test('registers a Tracker whose tokens go to secrets, not kv', () async {
    final tracker = malFeature(env, clientId: 'cid').services.single;
    expect(tracker, isA<Tracker>());
    body = fixture('token_ok.json');
    await (tracker as Tracker).login();
    final form = Uri.splitQueryString(http.requests.single.body!);
    expect(form['redirect_uri'], 'kartka://oauth');
    expect(form['client_id'], 'cid');
    expect((await secrets.entries()).keys, [StringMalTokenStore.defaultKey]);
    expect(await kv.entries(), isEmpty);
    expect(await tracker.isLoggedIn(), isTrue);
    await tracker.logout();
    expect(await secrets.entries(), isEmpty);
  });
}
