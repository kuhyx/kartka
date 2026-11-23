import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/app/registry.dart';
import 'package:kartka/library/library_repositories.dart';
import 'package:kartka/platform/key_value_store.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:kartka/platform/split_key_value_store.dart';

/// A store that never answers: the deferred kv still reading.
class _Never implements KeyValueStore {
  Future<T> _wait<T>() => Completer<T>().future;
  @override
  Future<String?> get(String key) => _wait();
  @override
  Future<void> set(String key, String value) => _wait();
  @override
  Future<void> remove(String key) => _wait();
  @override
  Future<Map<String, String>> entries({String prefix = ''}) => _wait();
}

/// library.load a133bbb8: with every feature registered, the library's
/// first rows (entries, categories, membership) need nothing under the
/// deferred prefixes, so the sync state and chapter lists can load after.
void main() {
  test('the library loads while the deferred kv never answers', () async {
    final kv = SplitKeyValueStore(
      MemoryKeyValueStore(),
      _Never(),
      deferredPrefixes: kvDeferredPrefixes,
    );
    final registry = KartkaRegistry.build(
      memoryPlatform(kv: kv),
      kartkaFeatureFactories,
    );
    final repos = registry.maybe<LibraryRepositories>()!;
    const wait = Duration(seconds: 5);
    expect(await repos.library.watch().first.timeout(wait), isEmpty);
    expect(await repos.categories.watch().first.timeout(wait), isNotNull);
    expect(
      await repos.categories.watchMembership().first.timeout(wait),
      isEmpty,
    );
  });
}
