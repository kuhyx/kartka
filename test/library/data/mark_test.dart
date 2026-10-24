import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/library/data/mark.dart';

final _t = DateTime.utc(2026, 10, 24, 12);

void main() {
  test('json round-trips', () {
    final m = Mark(key: 'k', target: 'c', on: true, at: _t);
    expect(Mark.fromJson(m.toJson()), m);
    expect(Mark.fromJson(m.toJson()).hashCode, m.hashCode);
    expect(m.toJson()['at'], _t.millisecondsSinceEpoch);
  });

  test('flip is null when nothing changes', () {
    final m = Mark(key: 'k', target: 'c', on: true, at: _t);
    expect(flip(m, 'k', 'c', on: true, now: _t), isNull);
    expect(flip(null, 'k', 'c', on: false, now: _t), isNull);
  });

  test('flip stamps now truncated to whole ms', () {
    final now = _t.add(const Duration(microseconds: 1500));
    final m = flip(null, 'k', 'c', on: true, now: now)!;
    expect(m.at, _t.add(const Duration(milliseconds: 1)));
    expect(Mark.fromJson(m.toJson()), m);
  });

  test('flip steps past a mark from the future', () {
    final ahead = Mark(key: 'k', target: 'c', on: true, at: _t);
    final m = flip(ahead, 'k', 'c', on: false, now: _t)!;
    expect(m.at, _t.add(const Duration(milliseconds: 1)));
    expect(m.on, isFalse);
  });
}
