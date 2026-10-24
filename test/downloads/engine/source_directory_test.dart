import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/source/source_provider.dart';
import 'package:kartka/downloads/engine/source_directory.dart';

import '../fakes.dart';

class _LiveProvider implements SourceProvider {
  final controller = StreamController<List<FakeSource>>.broadcast();

  @override
  Stream<List<FakeSource>> watch() => controller.stream;
}

void main() {
  test('finds sources from every provider, by id', () async {
    final a = FakeSource(id: 'a');
    final b = FakeSource(id: 'b');
    final dir = SourceDirectory(
      () => [
        StaticSourceProvider([a]),
        StaticSourceProvider([b]),
      ],
    );
    expect(await dir.find('b'), same(b));
    expect(await dir.find('a'), same(a));
    expect(await dir.find('zzz'), isNull);
    await dir.dispose();
  });

  test('picks up sources a provider adds later', () async {
    final live = _LiveProvider();
    final dir = SourceDirectory(
      () => [live],
      firstEmission: const Duration(milliseconds: 10),
    );
    expect(await dir.find('p'), isNull); // provider silent: times out
    live.controller.add([FakeSource(id: 'p')]);
    await pumpEventQueue();
    expect((await dir.find('p'))?.ref.id, 'p');
    live.controller.add([]);
    await pumpEventQueue();
    expect(await dir.find('p'), isNull);
    await dir.dispose();
  });
}
