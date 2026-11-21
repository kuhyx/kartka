import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/source/manga_source.dart';
import 'package:kartka/core/source/source_provider.dart';
import 'package:kartka/reader/data/source_lookup.dart';

import '../support/fakes.dart';

class _Silent implements SourceProvider {
  @override
  Stream<List<MangaSource>> watch() =>
      StreamController<List<MangaSource>>().stream;
}

class _Broken implements SourceProvider {
  @override
  Stream<List<MangaSource>> watch() => Stream.error(StateError('down'));
}

class _Throws implements SourceProvider {
  @override
  Stream<List<MangaSource>> watch() => throw StateError('no runtime');
}

/// Lists what [stream] emits and counts the subscriptions.
class _Of implements SourceProvider {
  new(this.stream);

  final Stream<List<MangaSource>> stream;
  int watches = 0;

  @override
  Stream<List<MangaSource>> watch() {
    watches++;
    return stream;
  }
}

SourceLookup _lookup(List<SourceProvider> providers) =>
    SourceLookup(() => providers);

void main() {
  test('finds a source by id across providers', () async {
    final a = FakeSource(id: 'a');
    final b = FakeSource(id: 'b');
    final lookup = _lookup([
      StaticSourceProvider([a]),
      _Broken(),
      StaticSourceProvider([b]),
      _Of(const Stream.empty()),
    ]);
    expect(await lookup.find('b'), same(b));
    expect(await lookup.find('a'), same(a));
    expect(await lookup.find('zzz'), isNull);
  });

  test('a provider that never emits does not hang the reader', () async {
    final lookup = _lookup([_Silent()]);
    final found = lookup.find('x', wait: const Duration(milliseconds: 10));
    expect(await found, isNull);
  });

  test('a slow provider does not delay the one that has the source '
      '(971debc8)', () async {
    final found = await _lookup([
      _Silent(),
      StaticSourceProvider([FakeSource(id: 'x')]),
    ]).find('x').timeout(const Duration(seconds: 1));
    expect(found?.ref.id, 'x');
  });

  test('no providers, or one that throws, is a miss', () async {
    expect(await _lookup(const []).find('x'), isNull);
    expect(await _lookup([_Throws()]).find('x'), isNull);
  });

  test('a later provider is found once it emits, before a miss is '
      'decided', () async {
    final late = StreamController<List<MangaSource>>();
    final source = FakeSource(id: 'y');
    final found = _lookup([
      StaticSourceProvider([FakeSource(id: 'x')]),
      _Of(late.stream),
    ]).find('y');
    late.add([source]);
    expect(await found, same(source));
    await late.close();
  });

  test('lists are kept: later lookups subscribe to nothing new and see '
      'changes (971debc8)', () async {
    // Each open re-listed every provider: a cold miss took 0.83 s on the
    // web build, and the extension host lists all its sources per call.
    final lists = StreamController<List<MangaSource>>.broadcast();
    final provider = _Of(lists.stream);
    final lookup = _lookup([provider]);
    final first = lookup.find('a');
    lists.add([FakeSource(id: 'a')]);
    expect((await first)?.ref.id, 'a');
    expect(await lookup.find('b'), isNull, reason: 'every list is in');
    lists.add([FakeSource(id: 'b')]);
    await pumpEventQueue();
    expect((await lookup.find('b'))?.ref.id, 'b');
    expect(provider.watches, 1);
    await lists.close();
  });
}
