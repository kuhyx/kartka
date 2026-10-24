import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:kartka/tracking/mangaupdates/mu_models.dart';
import 'package:kartka/tracking/mangaupdates/mu_session.dart';

void main() {
  late MemoryKeyValueStore kv;
  late MuSessionStore store;

  setUp(() {
    kv = MemoryKeyValueStore();
    store = MuSessionStore(kv);
  });

  test('round-trips and clears', () async {
    await store.write(const MuSession(token: 't', username: 'u'));
    final s = (await store.read())!;
    expect((s.token, s.username), ('t', 'u'));
    await store.clear();
    expect(await store.read(), isNull);
  });

  test('unreadable values read as logged out', () async {
    for (final raw in ['not json', '[]', '{"token": 1}', '{"token": "t"}']) {
      await kv.set(MuSessionStore.defaultKey, raw);
      expect(await store.read(), isNull, reason: raw);
    }
  });

  test('custom key', () async {
    final other = MuSessionStore(kv, key: 'k');
    await other.write(const MuSession(token: 't', username: 'u'));
    expect((await kv.entries()).keys, ['k']);
  });

  group('models', () {
    test('series needs id and title', () {
      expect(
        () => MuSeries.fromJson(const {'title': 'x'}),
        throwsFormatException,
      );
      final s = MuSeries.fromJson(const {'series_id': 1.0, 'title': 'x'});
      expect((s.id, s.coverUrl, s.type), (1, null, null));
    });

    test('list item needs series and list id; chapter defaults to 0', () {
      expect(
        () => MuListItem.fromJson(const {'list_id': 0}),
        throwsFormatException,
      );
      final i = MuListItem.fromJson(const {
        'series': {'id': 5},
        'list_id': 2,
        'list_type': '',
      });
      expect((i.chapter, i.status), (0, 'complete'));
    });

    test('exceptions print kind and status', () {
      expect('${const MuException('m')}', 'MuException: m');
      expect(
        '${const MuAuthException('m', statusCode: 401)}',
        'MuAuthException(401): m',
      );
    });
  });
}
