// Every lib/ file that can run on the VM must be imported by one of the
// test/all_imports/*_test.dart files, so `flutter test --coverage` reports it
// (an unloaded file is silently missing from lcov, which makes a 100 % figure
// hollow). Regenerate them with `python3 scripts/gen_all_imports.py .`.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('imports every lib/ file except coverage:ignore-file wiring', () {
    final pattern = RegExp("^import 'package:kartka/(.+)';", multiLine: true);
    final imported = {
      for (final f in Directory(
        'test/all_imports',
      ).listSync().whereType<File>())
        for (final m in pattern.allMatches(f.readAsStringSync()))
          'lib/${m.group(1)}',
    };
    final expected = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !_ignored(f))
        .map((f) => f.path.replaceAll(r'\', '/'))
        .toSet();
    expect(imported, expected);
  });
}

bool _ignored(File f) {
  final text = f.readAsStringSync();
  final head = text.substring(0, text.length.clamp(0, 400));
  // A `part of` file is loaded (and covered) through its library.
  return head.contains('coverage:ignore-file') ||
      RegExp('^part of ', multiLine: true).hasMatch(head);
}
