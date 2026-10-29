import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/downloads/engine/keyed_changes.dart';

void main() {
  test('notify reaches the key and the all-stream, nobody else', () {
    final changes = KeyedChanges();
    var a = 0;
    var b = 0;
    var all = 0;
    changes.of('a').listen((_) => a++);
    changes.of('b').listen((_) => b++);
    changes.all.listen((_) => all++);
    changes
      ..notify('a')
      ..notify('a')
      ..notify('unwatched');
    expect((a, b, all), (2, 0, 3));
  });

  test('notifyAll reaches every key', () {
    final changes = KeyedChanges();
    var hits = 0;
    changes.of('a').listen((_) => hits++);
    changes.of('a').listen((_) => hits++);
    changes.of('b').listen((_) => hits++);
    changes.notifyAll();
    expect(hits, 3);
  });

  test(
    'a stream not yet listened to survives another watcher leaving',
    () async {
      final changes = KeyedChanges();
      final early = changes.of('a');
      await changes.of('a').listen((_) {}).cancel();
      var hits = 0;
      early.listen((_) => hits++);
      changes.notify('a');
      expect(hits, 1);
    },
  );

  test('a cancelled watcher is no longer told, the others are', () async {
    final changes = KeyedChanges();
    var gone = 0;
    var kept = 0;
    final sub = changes.of('a').listen((_) => gone++);
    changes.of('a').listen((_) => kept++);
    await sub.cancel();
    changes
      ..notify('a')
      ..notifyAll();
    expect((gone, kept), (0, 2));
  });
}
