import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/source/manga_source.dart';
import 'package:kartka/core/source/source_provider.dart';
import 'package:kartka/migration/migration_target.dart';

import 'fakes.dart';

class _Later implements SourceProvider {
  final controller = StreamController<List<MangaSource>>.broadcast();

  @override
  Stream<List<MangaSource>> watch() => controller.stream;
}

void main() {
  test('titles match exactly up to case and spacing', () {
    expect(isExactTitle(' One  Piece', 'one piece'), isTrue);
    expect(isExactTitle('One Piece', 'One Piece!'), isFalse);
  });

  test('Atsumaru is found by its Suwayomi id or by name', () async {
    final byId = ScriptedSource(atsumaruSourceId, name: 'Other name');
    final byName = ScriptedSource('plugin:atsu', name: 'atsumaru');
    expect(
      await findTarget([
        StaticSourceProvider([ScriptedSource('mangadex'), byId]),
      ]),
      same(byId),
    );
    expect(
      await findTarget([
        StaticSourceProvider([byName]),
      ]),
      same(byName),
    );
  });

  test('a source that appears later is waited for', () async {
    final later = _Later();
    final found = findTarget([later]);
    later.controller.add(const []);
    final atsu = ScriptedSource(atsumaruSourceId);
    later.controller.add([atsu]);
    expect(await found, same(atsu));
  });

  test('no Atsumaru within the timeout is null', () async {
    final later = _Later();
    expect(
      await findTarget([later], timeout: const Duration(milliseconds: 10)),
      isNull,
    );
    expect(await findTarget(const []), isNull);
  });
}
