import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/app/feature.dart';
import 'package:kartka/platform/platform.dart';
import 'package:kartka/tracking/common/tracker.dart';
import 'package:kartka/tracking/mal/mal_feature.dart';
import 'package:kartka/tracking/mal/mal_http.dart';
import 'package:kartka/tracking/mal/mal_tokens.dart';
import 'package:kartka/tracking/mal/mal_transport.dart';

import 'mal_fakes.dart';

class _Http extends KartkaHttp {
  final List<(String, Uri, Map<String, String>, String?)> calls = [];
  int status = 200;
  String body = '{}';

  @override
  Future<KartkaResponse> send(
    String method,
    Uri url, {
    Map<String, String> headers = const {},
    String? body,
  }) async {
    calls.add((method, url, headers, body));
    return KartkaResponse(
      statusCode: status,
      bodyBytes: Uint8List.fromList(utf8.encode(this.body)),
    );
  }
}

class _Kv implements KeyValueStore {
  final Map<String, String> data = {};

  @override
  Future<String?> get(String key) async => data[key];

  @override
  Future<void> set(String key, String value) async => data[key] = value;

  @override
  Future<void> remove(String key) async => data.remove(key);

  @override
  Future<Map<String, String>> entries({String prefix = ''}) async => {
    for (final e in data.entries)
      if (e.key.startsWith(prefix)) e.key: e.value,
  };
}

class _OAuth implements OAuthRedirect {
  @override
  Uri get redirectUri => Uri.parse('kartka://oauth');

  @override
  Future<Uri> authorize(
    Uri authorizationUrl, {
    Duration timeout = const Duration(minutes: 5),
  }) async => Uri.parse(
    'kartka://oauth?code=c&state=${authorizationUrl.queryParameters['state']}',
  );
}

class _Unused implements BlobStore, FilePicker {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  late _Http http;
  late _Kv secrets;
  late _Kv kv;
  late KartkaEnv env;

  setUp(() {
    http = _Http();
    secrets = _Kv();
    kv = _Kv();
    env = KartkaEnv(
      KartkaPlatform(
        http: http,
        blobs: _Unused(),
        kv: kv,
        secrets: secrets,
        filePicker: _Unused(),
        oauth: _OAuth(),
      ),
    );
  });

  test('adapter forwards method, headers and body', () async {
    http
      ..status = 201
      ..body = 'ok';
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
    expect(http.calls.single.$1, 'PATCH');
    expect(http.calls.single.$3, {'H': 'v'});
    expect(http.calls.single.$4, 'b=1');
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
    http.body = fixture('token_ok.json');
    await (tracker as Tracker).login();
    final form = Uri.splitQueryString(http.calls.single.$4!);
    expect(form['redirect_uri'], 'kartka://oauth');
    expect(form['client_id'], 'cid');
    expect(secrets.data.keys, [StringMalTokenStore.defaultKey]);
    expect(kv.data, isEmpty);
    expect(await tracker.isLoggedIn(), isTrue);
    await tracker.logout();
    expect(secrets.data, isEmpty);
  });
}
