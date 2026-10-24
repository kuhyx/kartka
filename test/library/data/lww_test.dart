import 'package:glados/glados.dart';
import 'package:kartka/library/data/lww.dart';

typedef _Rec = ({int at, String v});

_Rec _merge(_Rec a, _Rec b) => lwwMerge(
  a,
  b,
  at: (r) => DateTime.utc(2026).add(Duration(milliseconds: r.at)),
  tie: (r) => r.v,
);

extension on Any {
  // Small ranges so equal timestamps (the tie-break path) are common.
  Generator<_Rec> get rec => combine2(
    intInRange(0, 4),
    choose(['a', 'b', 'c']),
    (at, v) => (at: at, v: v),
  );
}

void main() {
  test('newer timestamp wins regardless of argument order', () {
    const old = (at: 1, v: 'z');
    const fresh = (at: 2, v: 'a');
    expect(_merge(old, fresh), fresh);
    expect(_merge(fresh, old), fresh);
  });

  test('equal timestamps fall back to the greater tie string', () {
    const a = (at: 1, v: 'a');
    const b = (at: 1, v: 'b');
    expect(_merge(a, b), b);
    expect(_merge(b, a), b);
  });

  test('nextStamp is strictly after the current stamp', () {
    final t = DateTime.utc(2026);
    expect(nextStamp(t, null), t);
    expect(nextStamp(t, t.subtract(const Duration(seconds: 1))), t);
    expect(nextStamp(t, t), t.add(const Duration(milliseconds: 1)));
    final ahead = t.add(const Duration(hours: 1));
    expect(nextStamp(t, ahead), ahead.add(const Duration(milliseconds: 1)));
  });

  test('utcNow is the current instant in UTC', () {
    final now = utcNow();
    expect(now.isUtc, isTrue);
    expect(DateTime.now().difference(now).inSeconds.abs(), lessThan(5));
  });

  Glados2(any.rec, any.rec).test('commutative', (a, b) {
    expect(_merge(a, b), _merge(b, a));
  });

  Glados3(any.rec, any.rec, any.rec).test('associative', (a, b, c) {
    expect(_merge(_merge(a, b), c), _merge(a, _merge(b, c)));
  });

  Glados(any.rec).test('idempotent', (a) => expect(_merge(a, a), a));
}
