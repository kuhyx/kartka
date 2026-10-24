// The platform seam is only real if nothing outside it reaches past it:
// `dart:io` compiles for web and then throws at runtime (a blank window), and
// web-only libraries break the Android and VM builds. SPEC + §2/§7.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Import prefix -> the only lib/ directory allowed to use it.
const _rules = {
  'dart:io': 'lib/platform/io/',
  'dart:js_interop': 'lib/platform/web/',
  'dart:html': 'lib/platform/web/',
  'package:web/': 'lib/platform/web/',
  'package:http/': 'lib/platform/',
  'package:file_picker/': 'lib/platform/',
  'package:path_provider/': 'lib/platform/io/',
  'package:idb_shim/': 'lib/platform/web/',
};

final _directive = RegExp(
  r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
  multiLine: true,
);

/// Violations in [files] as `path: uri` strings.
List<String> violations(Iterable<File> files) => [
  for (final file in files)
    for (final match in _directive.allMatches(file.readAsStringSync()))
      for (final rule in _rules.entries)
        if (match.group(1)!.startsWith(rule.key) &&
            !file.path.replaceAll(r'\', '/').contains(rule.value))
          '${file.path}: ${match.group(1)}',
];

void main() {
  test('lib/ respects the platform seam', () {
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    expect(violations(files), isEmpty);
  });

  test('the scanner catches a violation', () {
    final dir = Directory.systemTemp.createTempSync('kartka_seam');
    addTearDown(() => dir.deleteSync(recursive: true));
    final bad = File('${dir.path}/lib/sources/x.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        "import 'dart:io';\nimport 'package:http/http.dart';",
      );
    final ok = File('${dir.path}/lib/platform/io/y.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync("import 'dart:io';");
    expect(violations([bad, ok]), hasLength(2));
  });
}
