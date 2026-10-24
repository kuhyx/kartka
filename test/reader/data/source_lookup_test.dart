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
}
