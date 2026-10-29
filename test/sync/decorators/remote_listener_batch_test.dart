import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/sync/decorators/remote_listener.dart';
import 'package:kartka/sync/merge/merge_rules.dart';
import 'package:kartka/sync/rtdb_transport.dart';
import 'package:kartka/sync/sync_engine.dart';

import '../fakes.dart';

/// Records the batches `apply` sees; fails for paths in [failing].
class _Probe with RemoteListener {
  new(Future<SyncEngine> engine, {this.failing = const {}}) {
    listen(engine, {'library'});
  }

  final Set<String> failing;
  final started = <String>[];
  final done = <String>[];

  @override
  Future<void> apply(SyncEngine engine, RemoteChange change) async {
    started.add(change.path);
    await Future<void>.delayed(Duration.zero);
    if (failing.contains(change.path)) throw StateError('boom');
    done.add(change.path);
  }
}

Node _node(String hlc, String title) => {
  'key': 'k',
  'title': title,
  kHlcField: {'key': hlc, 'title': hlc},
};

void main() {
  late InMemoryRtdb db;
  late SyncEngine writer;
  late SyncEngine reader;

  setUp(() async {
    db = InMemoryRtdb();
    writer = await engineFor('dev-a', db);
    reader = await engineFor('dev-b', db);
  });

  test('changes of one turn start together, in order, and are acked after '
      'their write', () async {
    final probe = _Probe(Future.value(reader));
    final hlc = writer.tick().toStr();
    await writer.writeAll({
      for (var i = 0; i < 5; i++) 'library/h$i': _node(hlc, 't$i'),
    });
    await reader.poll();
    await probe.settled;
    expect(probe.started, [for (var i = 0; i < 5; i++) 'library/h$i']);
    expect(probe.done, probe.started);
    expect(reader.shadow.unapplied, isEmpty, reason: 'every path acked');
    await probe.dispose();
  });

  test('a failing apply is not acked and does not stop its batch', () async {
    final probe = _Probe(Future.value(reader), failing: {'library/h1'});
    final hlc = writer.tick().toStr();
    await writer.writeAll({
      for (var i = 0; i < 3; i++) 'library/h$i': _node(hlc, 't$i'),
    });
    await reader.poll();
    await expectLater(probe.settled, throwsStateError);
    expect(probe.done, ['library/h0', 'library/h2']);
    expect(reader.shadow.unapplied, {'library/h1'}, reason: 'replayed later');
    await probe.dispose();
  });
}
