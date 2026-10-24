// Live smoke test against the real MAL API: checks that the documented
// shapes the fixtures were built from still hold. Excluded by default
// (dart_test.yaml skips `live`). Run after tools/tracking/register_mal.sh:
//   fvm flutter test --run-skipped --tags live test/tracking/mal
@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:kartka/tracking/mal/mal_api.dart';
import 'package:kartka/tracking/mal/mal_auth.dart';
import 'package:kartka/tracking/mal/mal_session.dart';
import 'package:kartka/tracking/mal/mal_transport.dart';

import 'mal_fakes.dart';

String? _clientId() {
  final env = Platform.environment['KARTKA_MAL_CLIENT_ID_WEB'];
  if (env != null && env.isNotEmpty) return env;
  final home = Platform.environment['HOME'];
  final file = File('$home/.config/kartka/oauth.json');
  if (!file.existsSync()) return null;
  final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  return json['KARTKA_MAL_CLIENT_ID_WEB'] as String?;
}

Future<MalResponse> _send(MalRequest r) async {
  final res = await http.get(r.url, headers: r.headers);
  return MalResponse(res.statusCode, res.body);
}

void main() {
  final id = _clientId();

  test('search finds Berserk (id 2) in the documented shape', () async {
    final store = MemoryTokenStore();
    final api = MalApi(
      clientId: id!,
      send: _send,
      session: MalSession(
        auth: MalAuth(
          client: MalOAuthClient(clientId: id, redirectUri: 'kartka://oauth'),
          send: _send,
          store: store,
          launch: (_) => throw UnsupportedError('no login in smoke test'),
        ),
        store: store,
        send: _send,
      ),
    );
    final results = await api.search('Berserk');
    final berserk = results.firstWhere((m) => m.id == 2);
    expect(berserk.title, 'Berserk');
    expect(berserk.coverUrl, startsWith('https://'));
  }, skip: id == null ? 'no MAL client id; run register_mal.sh' : false);
}
