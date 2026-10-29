import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/updates/data/update_feed.dart';

ChapterInfo _ch(int n) =>
    ChapterInfo(url: '/c/$n', name: 'Ch. $n', number: n.toDouble());

void main() {
  final a = mangaKeyOf('mangadex', '/a');
  final stranger = mangaKeyOf('mangadex', '/not-in-library');
  late MemoryKeyValueStore kv;
  late DateTime now;
  UpdateFeed feed({int cap = 500}) => UpdateFeed(
    kv,
    inLibrary: (key) async => key != stranger,
    clock: () => now,
    cap: cap,
  );

  setUp(() {
    kv = MemoryKeyValueStore();
    now = DateTime.utc(2026, 10, 29, 12);
  });

  test('records added chapters newest first, persisted', () async {
    final f = feed();
    var notified = 0;
    f.addListener(() => notified++);
    await f.record(a, [_ch(3), _ch(4)]);
    expect([for (final e in f.events) e.chapter.url], ['/c/4', '/c/3']);
    expect(f.events.first.key, a);
    expect(f.events.first.foundAt, now);
    expect(notified, greaterThan(0));

    final restored = feed();
    await restored.load();
    expect(restored.loaded, isTrue);
    expect(restored.events, f.events);
  });

  test('dedups a chapter recorded twice (detail + update-all race)', () async {
    final f = feed();
    await Future.wait([
      f.record(a, [_ch(3)]),
      f.record(a, [_ch(3)]),
    ]);
    expect(f.events, hasLength(1));
  });

  test('ignores manga outside the library and empty batches', () async {
    final f = feed();
    await f.record(stranger, [_ch(1)]);
    await f.record(a, const []);
    expect(f.events, isEmpty);
    expect(await kv.entries(), isEmpty);
  });

  test('keeps the newest [cap] events and drops ones over 60 days', () async {
    final f = feed(cap: 3);
    now = DateTime.utc(2026, 8);
    await f.record(a, [_ch(1)]);
    now = DateTime.utc(2026, 10, 29);
    await f.record(a, [_ch(2), _ch(3)]);
    expect([for (final e in f.events) e.chapter.url], ['/c/3', '/c/2']);
    await f.record(a, [_ch(4), _ch(5)]);
    expect([for (final e in f.events) e.chapter.url], ['/c/5', '/c/4', '/c/3']);
  });

  test('a stored event past 60 days is pruned on load', () async {
    now = DateTime.utc(2026, 8);
    await feed().record(a, [_ch(1)]);
    now = DateTime.utc(2026, 10, 29);
    final f = feed();
    await f.load();
    expect(f.events, isEmpty);
  });

  test('a corrupt stored feed loads as empty, load runs once', () async {
    await kv.set(UpdateFeed.storageKey, '{not json');
    final f = feed();
    await Future.wait([f.load(), f.load()]);
    expect(f.events, isEmpty);
    await f.record(a, [_ch(1)]);
    expect(f.events, hasLength(1));
  });

  test('event json round-trips and compares by value', () {
    final e = UpdateEvent(key: a, chapter: _ch(1), foundAt: now);
    expect(UpdateEvent.fromJson(e.toJson()), e);
    expect(UpdateEvent.fromJson(e.toJson()).hashCode, e.hashCode);
    expect(e == UpdateEvent(key: a, chapter: _ch(2), foundAt: now), isFalse);
  });
}
