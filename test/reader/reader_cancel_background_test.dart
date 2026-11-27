import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/app/feature.dart';
import 'package:kartka/core/source/shown_page_gate.dart';
import 'package:kartka/platform/memory/memory_extension_runtime.dart';
import 'package:kartka/platform/memory/memory_platform.dart';
import 'package:kartka/reader/logic/shown_page_wait.dart';
import 'package:kartka/reader/reader_feature.dart';

void main() {
  // 64f0bd6f: downloads already in flight slowed an open's page list and
  // page 1 from 0.2 s to 1 s each, so each shown page that starts loading
  // has the extension host cancel them (the engine fetches them again).
  test('a shown page that starts loading cancels background calls', () {
    final runtime = FakeExtensionRuntime();
    final registry = KartkaRegistry.build(memoryPlatform(extensions: runtime), [
      readerFeature,
    ]);
    final gate = registry.all<ShownPageGate>().single as ShownPageWait;
    final page = Completer<int>();
    gate
      ..hold(1, page.future)
      ..hold(1, page.future);
    expect(runtime.calls.map((c) => c.$1), ['cancelBackground']);
  });

  test('the web build, with no extension host, cancels nothing', () {
    final registry = KartkaRegistry.build(memoryPlatform(), [readerFeature]);
    (registry.all<ShownPageGate>().single as ShownPageWait).hold(
      1,
      Completer<int>().future,
    );
  });
}
