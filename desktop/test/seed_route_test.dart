import 'dart:convert';

import 'package:kartka_desktop/kartka_desktop.dart';
import 'package:test/test.dart';

import 'helpers.dart';

// Obviously fake values: the route never looks inside them.
const _seed = {
  'id_token': 'fake-id',
  'refresh_token': 'fake-refresh',
  'expires_at': '2026-10-24T12:00:00.000Z',
};

void main() {
  late Harness h;
  tearDown(() => h.close());

  test('without the flag the route does not exist', () async {
    h = await Harness.start();
    expect((await h.call('GET', syncCredentialsPath)).status, 404);
  });

  test('serves the seed once per launch, then 410', () async {
    h = await Harness.start(seed: jsonEncode({..._seed, 'email': 'a@b.c'}));
    final first = await h.call('GET', syncCredentialsPath);
    expect(first.status, 200);
    expect(first.headers.contentType!.mimeType, 'application/json');
    expect(first.headers.value('cache-control'), 'no-store');
    expect(first.headers.value('access-control-allow-origin'), isNull);
    expect(jsonDecode(text(first)), {..._seed, 'email': 'a@b.c'});
    expect((await h.call('GET', syncCredentialsPath)).status, 410);
  });

  test('passes only the session fields (and a string email)', () async {
    h = await Harness.start(
      seed: jsonEncode({..._seed, 'email': 7, 'other': 'x'}),
    );
    expect(jsonDecode(text(await h.call('GET', syncCredentialsPath))), _seed);
  });

  test('two concurrent requests: exactly one 200', () async {
    h = await Harness.start(seed: jsonEncode(_seed));
    final replies = await Future.wait([
      h.call('GET', syncCredentialsPath),
      h.call('GET', syncCredentialsPath),
    ]);
    expect(replies.map((r) => r.status).toList()..sort(), [200, 410]);
  });

  test('refusals never consume the seed', () async {
    h = await Harness.start(seed: jsonEncode(_seed));
    expect((await h.call('GET', syncCredentialsPath, api: false)).status, 403);
    final rebound = await h.call('GET', syncCredentialsPath, host: 'evil.ex');
    expect(rebound.status, 421);
    expect((await h.call('POST', syncCredentialsPath)).status, 405);
    expect((await h.call('HEAD', syncCredentialsPath)).status, 405);
    expect((await h.call('GET', syncCredentialsPath)).status, 200);
  });

  test('a missing file answers 404 and keeps the route open', () async {
    final lines = <String>[];
    h = await Harness.start(seedFile: true, log: lines.add);
    expect((await h.call('GET', syncCredentialsPath)).status, 404);
    expect(lines.single, contains('no seeded session'));
  });

  test('malformed or incomplete seeds: 404, no content in the log', () async {
    for (final bad in [
      '{"id_token": "secret-ish", "refresh_tok',
      '["secret-ish"]',
      jsonEncode({..._seed, 'expires_at': 1, 'id_token': 'secret-ish'}),
    ]) {
      final lines = <String>[];
      h = await Harness.start(seed: bad, log: lines.add);
      expect((await h.call('GET', syncCredentialsPath)).status, 404);
      expect(lines, hasLength(1), reason: bad);
      expect(lines.single, isNot(contains('secret-ish')));
      expect(lines.single, contains('not serving it'));
      await h.close();
    }
    h = await Harness.start();
  });
}
