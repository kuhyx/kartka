import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/platform/key_value_store.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/platform/split_key_value_store.dart';

/// A memory store that decodes by key and counts its flushes.
class _Decoding extends MemoryKeyValueStore implements OffUiDecodingStore {
  new([super.seed]);
  int decodeCalls = 0;
  int flushes = 0;
  Future<void> flush() async => flushes++;
  @override
  Future<List<R?>> decodeAll<R extends Object>(
    List<String> keys,
    R? Function(String text) decode,
  ) async {
    decodeCalls++;
    return [
      for (final k in keys)
        if (await get(k) case final t?) decode(t) else null,
    ];
  }
}

/// library.load a133bbb8: `sync.` and `browse.chapters.` (13 of the 20 MB
/// the phone read before its first library paint) live in a second store,
/// read after the first; nothing else moves.
void main() {
  late _Decoding fast;
  late _Decoding deferred;
  late SplitKeyValueStore kv;

  setUp(() {
    fast = _Decoding({
      'library/a': 'L',
      'sync.b.read/x': 'old-in-fast',
      'browse.chapters.h1': '[1]',
    });
    deferred = _Decoding();
    kv = SplitKeyValueStore(
      fast,
      deferred,
      deferredPrefixes: kvDeferredPrefixes,
      flushFast: fast.flush,
      flushDeferred: deferred.flush,
    );
  });

  test('defers sync state and chapter lists only', () {
    expect(kvDeferredPrefixes, ['sync.', 'browse.chapters.']);
    expect(kv.isDeferred('sync.hlc'), isTrue);
    expect(kv.isDeferred('browse.chapters.h'), isTrue);
    expect(kv.isDeferred('browse.languages'), isFalse);
    expect(kv.isDeferred('library/a'), isFalse);
  });

  test("writes go to the key's store; reads fall back until moved", () async {
    await kv.set('library/b', 'L2');
    await kv.set('sync.hlc', '7');
    expect(await fast.get('library/b'), 'L2');
    expect(await deferred.get('sync.hlc'), '7');
    expect(await fast.get('sync.hlc'), isNull);
    expect(await kv.get('sync.b.read/x'), 'old-in-fast');
    await kv.set('sync.b.read/x', 'new');
    expect(await kv.get('sync.b.read/x'), 'new', reason: 'deferred wins');
    expect(await kv.get('library/a'), 'L');
  });

  test('remove clears both copies, so an old one cannot come back', () async {
    await deferred.set('sync.b.read/x', 'new');
    await kv.remove('sync.b.read/x');
    expect(await kv.get('sync.b.read/x'), isNull);
    await kv.remove('library/a');
    expect(await kv.get('library/a'), isNull);
  });

  test(
    'entries merge both stores where a prefix reaches deferred keys',
    () async {
      await deferred.set('sync.b.read/x', 'new');
      await deferred.set('sync.hlc', '7');
      expect(await kv.entries(prefix: 'library/'), {'library/a': 'L'});
      expect(await kv.entries(prefix: 'sync.b.'), {'sync.b.read/x': 'new'});
      expect(await kv.entries(prefix: 'browse.'), {
        'browse.chapters.h1': '[1]',
      });
      expect(await kv.entries(), {
        'library/a': 'L',
        'sync.b.read/x': 'new',
        'browse.chapters.h1': '[1]',
        'sync.hlc': '7',
      });
    },
  );

  test('decodeAll asks each store by key, the fast one as fallback', () async {
    await deferred.set('browse.chapters.h2', '[2]');
    final out = await kv.decodeAll([
      'browse.chapters.h1',
      'browse.chapters.h2',
      'library/a',
      'nope',
    ], (t) => t);
    expect(out, ['[1]', '[2]', 'L', null]);
  });

  test(
    'migrate copies deferred keys over, then drops the fast copies',
    () async {
      await deferred.set('sync.b.read/x', 'newer');
      await kv.migrate();
      expect(await deferred.get('sync.b.read/x'), 'newer', reason: 'kept');
      expect(await deferred.get('browse.chapters.h1'), '[1]');
      expect(await fast.entries(), {'library/a': 'L'});
      expect(deferred.flushes, 1, reason: 'flushed before the removal');
      expect(fast.flushes, 1);
      await kv.migrate();
      expect(deferred.flushes, 1, reason: 'nothing left to move');
    },
  );

  test('a migration cut before the removal is finished next time', () async {
    // Copied and flushed, then the app died: both stores hold the keys.
    await deferred.set('browse.chapters.h1', '[1]');
    await deferred.set('sync.b.read/x', 'old-in-fast');
    await kv.migrate();
    expect(await fast.entries(), {'library/a': 'L'});
    expect(await kv.get('browse.chapters.h1'), '[1]');
  });

  test('flush writes both stores', () async {
    await kv.flush();
    expect([fast.flushes, deferred.flushes], [1, 1]);
  });

  test('plain stores decode on the caller; a failed fast read still '
      'opens the deferred store', () async {
    final plain = SplitKeyValueStore(
      _Failing(),
      MemoryKeyValueStore({'browse.chapters.h': '[3]'}),
      deferredPrefixes: kvDeferredPrefixes,
    );
    expect(await plain.decodeAll(['browse.chapters.h'], (t) => t), ['[3]']);
    expect(await plain.get('sync.x'), isNull);
    await plain.flush();
  });

  test(
    'the deferred store is touched only after the fast one answered',
    () async {
      final gate = Completer<void>();
      final order = <String>[];
      final slow = SplitKeyValueStore(
        _Gated(fast, gate.future, () => order.add('fast')),
        _Gated(deferred, Future.value(), () => order.add('deferred')),
        deferredPrefixes: kvDeferredPrefixes,
      );
      final read = slow.get('sync.hlc');
      await pumpEventQueue();
      expect(order, ['fast'], reason: 'waits for the fast read');
      gate.complete();
      await read;
      expect(order, ['fast', 'deferred']);
    },
  );
}

/// Answers only after its gate; its callback runs on the first call.
class _Gated implements KeyValueStore {
  new(this._inner, this._gate, this._touched);
  final KeyValueStore _inner;
  final Future<void> _gate;
  final void Function() _touched;
  var _first = true;

  Future<T> _after<T>(Future<T> Function() op) async {
    if (_first) {
      _first = false;
      _touched();
    }
    await _gate;
    return await op();
  }

  @override
  Future<String?> get(String key) => _after(() => _inner.get(key));
  @override
  Future<void> set(String key, String value) =>
      _after(() => _inner.set(key, value));
  @override
  Future<void> remove(String key) => _after(() => _inner.remove(key));
  @override
  Future<Map<String, String>> entries({String prefix = ''}) =>
      _after(() => _inner.entries(prefix: prefix));
}

/// A fast store whose read failed: it answers nothing for any key.
class _Failing extends MemoryKeyValueStore {
  @override
  Future<String?> get(String key) async =>
      key.isEmpty ? throw StateError('read failed') : null;
}
