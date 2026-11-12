// Pins the sealed node format the Python tools open
// (tools/errors and tools/source_eval, `e2e.py`). Regenerate with
// KARTKA_WRITE_E2E_VECTORS=1 only on a deliberate format change.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/sync/e2e/sealed_transport.dart';
import 'package:kartka/sync/rtdb_transport.dart';

import 'e2e_fixtures.dart';

const _hlc = '2026-11-12T10:00:00.000Z-0000-dev-a';

final Map<String, Map<String, Object?>> _nodes = {
  'settings/sourceHealth~2Escoring': {
    'key': 'sourceHealth.scoring',
    'value': '{"keepScore":0.8}',
    'hlc': _hlc,
  },
  'errors/dev-a/e1': {
    'at': '2026-11-12T10:00:00.000Z',
    'kind': 'ui.snackbar',
    'error': 'Zażółć: boom',
    'stack': ['#0 f'],
  },
  'read/h1/c1': {'read': false, 'hlc': _hlc},
};

void main() {
  final file = File('test/fixtures/e2e_vectors.json');

  test('the pinned vectors open to their nodes', () async {
    final cipher = await testCipher();
    if (Platform.environment['KARTKA_WRITE_E2E_VECTORS'] == '1') {
      final db = InMemoryRtdb();
      final t = SealedTransport(db, cipher);
      await t.patch(_nodes);
      Object? at(String path) => path
          .split('/')
          .fold<Object?>(db.tree, (n, s) => (n! as Map<String, Object?>)[s]);
      final vectors = {
        'key': '07' * 32,
        'nodes': [
          for (final MapEntry(:key, :value) in _nodes.entries)
            {'path': key, 'node': value, 'stored': at(key)},
        ],
      };
      const json = JsonEncoder.withIndent('  ');
      file.writeAsStringSync('${json.convert(vectors)}\n');
    }
    final vectors = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    expect(vectors['key'], '07' * 32);
    final cases = (vectors['nodes']! as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(cases.map((c) => c['path']), _nodes.keys);
    for (final c in cases) {
      final path = c['path']! as String;
      final db = InMemoryRtdb();
      await db.patch({path: c['stored']});
      expect(await SealedTransport(db, cipher).get(path), _nodes[path]);
    }
  });
}
