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

void main() {
  test('finds a source by id across providers', () async {
    final a = FakeSource(id: 'a');
    final b = FakeSource(id: 'b');
    final providers = [
      StaticSourceProvider([a]),
      _Broken(),
      StaticSourceProvider([b]),
    ];
    expect(await findSource(providers, 'b'), same(b));
    expect(await findSource(providers, 'a'), same(a));
    expect(await findSource(providers, 'zzz'), isNull);
  });

  test('a provider that never emits does not hang the reader', () async {
    final found = await findSource(
      [
        _Silent(),
        StaticSourceProvider([FakeSource(id: 'x')]),
      ],
      'x',
      wait: const Duration(milliseconds: 10),
    );
    expect(found?.ref.id, 'x');
  });

  test('a slow provider does not delay the one that has the source '
      '(971debc8)', () async {
    final found = await findSource([
      _Silent(),
      StaticSourceProvider([FakeSource(id: 'x')]),
    ], 'x').timeout(const Duration(seconds: 1));
    expect(found?.ref.id, 'x');
  });

  test('no providers, or one that throws, is a miss', () async {
    expect(await findSource(const [], 'x'), isNull);
    expect(await findSource([_Throws()], 'x'), isNull);
  });

  test('a later provider is found once it emits, before a miss is '
      'decided', () async {
    final late = StreamController<List<MangaSource>>();
    final source = FakeSource(id: 'y');
    final found = findSource([
      StaticSourceProvider([FakeSource(id: 'x')]),
      _Of(late.stream),
    ], 'y');
    late.add([source]);
    expect(await found, same(source));
    await late.close();
  });
}

class _Throws implements SourceProvider {
  @override
  Stream<List<MangaSource>> watch() => throw StateError('no runtime');
}

class _Of implements SourceProvider {
  const new(this._stream);
  final Stream<List<MangaSource>> _stream;
  @override
  Stream<List<MangaSource>> watch() => _stream;
}
