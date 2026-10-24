import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:kartka/tracking/common/binding_store.dart';
import 'package:kartka/tracking/common/track_binding.dart';
import 'package:kartka/tracking/common/tracked_lookup.dart';

import '../fakes.dart';

const _k = 'mangadex|/manga/abc';
const _b = TrackBinding(key: _k, service: 'anilist', remoteId: '1');

/// Records what it wrapped and passes calls through.
class _Tagging implements BindingStoreDecorator {
  final List<BindingStore> wrapped = [];

  @override
  BindingStore decorate(BindingStore inner) {
    wrapped.add(inner);
    return inner;
  }
}

void main() {
  test('isTracked follows bindings of the key', () async {
    final store = KvBindingStore(MemoryKeyValueStore());
    final seen = <bool>[];
    final sub = BindingTrackedLookup(store).isTracked(_k).listen(seen.add);
    await pumpEvents();
    await store.put(_b);
    await pumpEvents();
    await store.put(_b.copyWith(lastPushedChapter: 3));
    await pumpEvents();
    await store.remove(_k, 'anilist');
    await pumpEvents();
    await sub.cancel();
    expect(seen, [false, true, false]);
  });

  test('LazyBindingStore applies decorators once, on first use', () async {
    final base = KvBindingStore(MemoryKeyValueStore());
    final deco = _Tagging();
    var asked = 0;
    final lazy = LazyBindingStore(base, () {
      asked++;
      return [deco];
    });
    expect(asked, 0);
    await lazy.put(_b);
    expect(await lazy.all(), [_b]);
    expect(await lazy.watch(_k).first, [_b]);
    await lazy.remove(_k, 'anilist');
    expect(await lazy.all(), isEmpty);
    expect(asked, 1);
    expect(deco.wrapped, [base]);
  });
}
