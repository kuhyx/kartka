import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'session_fixture.dart';

/// The page-wait probe (28fffd0a): a shown page that spun 1 s or more is
/// logged as `reader.pagewait`, naming the step and the image host.
void main() {
  late SessionFixture f;
  setUp(() => f = SessionFixture());

  Future<List<String>> probes() async => [
    for (final e in await f.diagnostics.entries())
      if (e.kind == 'reader.pagewait') e.error,
  ];

  test('a shown page held 1.5 s names its fetch and host', () async {
    final gate = f.imageGates['https://img.test/c/2/0.png'] = Completer();
    final s = f.make();
    await s.open();
    s.image(0).ignore();
    f.clock = f.clock.add(const Duration(milliseconds: 1500));
    gate.complete();
    await pumpEventQueue();
    expect(await probes(), [
      contains(
        'ReaderProbe: page waited on fetch after turn over 1 s from img.test',
      ),
    ]);
  });

  test('a page already in is not timed; a quick one is not logged', () async {
    final s = f.make();
    await s.open();
    await s.image(0);
    f.clock = f.clock.add(const Duration(seconds: 3));
    await s.image(0);
    s.image(1).ignore();
    await pumpEventQueue();
    expect(await probes(), isEmpty);
  });

  test('an off-screen neighbour that spins is not timed', () async {
    final gate = f.imageGates['https://img.test/c/2/2.png'] = Completer();
    final s = f.make();
    await s.open();
    s.image(2).ignore();
    f.clock = f.clock.add(const Duration(seconds: 3));
    gate.complete();
    await pumpEventQueue();
    expect(await probes(), isEmpty);
  });
}
