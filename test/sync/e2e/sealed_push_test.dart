import 'package:crdt_sync/crdt_sync.dart' show E2eKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/sync/e2e/sealed_transport.dart';
import 'package:kartka/sync/merge/merge_rules.dart';
import 'package:kartka/sync/rtdb_transport.dart';
import 'package:kartka/sync/sync_engine.dart';
import 'package:kartka/sync/sync_shadow.dart';

void main() {
  test('a pushed library node holds no plaintext title', () async {
    final db = InMemoryRtdb();
    final key = await E2eKey.fromBytes(List.filled(32, 7));
    final sealed = SealedTransport(db, key.cipher(acceptPlaintext: false));
    final engine = SyncEngine(
      shadow: await SyncShadow.load(MemoryKeyValueStore()),
      deviceId: 'dev-a',
      open: () async => sealed,
    );
    final hlc = engine.tick().toStr();
    await engine.write('library/h1', {
      'key': 'mangadex|/m/1',
      'title': 'Berserk',
      kHlcField: {'key': hlc, 'title': hlc},
    });
    final stored = canon(db.tree);
    expect(stored, contains('library'));
    expect(stored, isNot(contains('Berserk')));
    expect(stored, isNot(contains('"title"')));
  });
}
