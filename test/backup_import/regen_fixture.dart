// Regenerates the committed synthetic backup:
//   fvm dart run test/backup_import/regen_fixture.dart
// ignore_for_file: avoid_print
import 'dart:io';

import 'fixture_builder.dart';

void main() {
  const path = 'test/fixtures/backup_import/synthetic.tachibk';
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(buildSyntheticTachibk());
  print('wrote $path');
}
