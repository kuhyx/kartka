import 'package:flutter_test/flutter_test.dart';
import 'package:idb_shim/idb_client_memory.dart';
import 'package:kartka/platform/web/idb_key_value_store.dart';

void main() {
  test('IdbKeyValueStore get/set/remove/entries and reopen', () async {
    final factory = newIdbFactoryMemory();
    final kv = await IdbKeyValueStore.open(factory);
    expect(await kv.get('a'), isNull);
    await kv.set('lib.x', '1');
    await kv.set('lib.y', 'ż');
    await kv.set('other', '3');
    await kv.remove('other');
    await kv.remove('missing');
    expect(await kv.entries(prefix: 'lib.'), {'lib.x': '1', 'lib.y': 'ż'});
    final again = await IdbKeyValueStore.open(factory);
    expect(await again.get('lib.y'), 'ż');
    expect(await again.entries(), hasLength(2));
  });
}
