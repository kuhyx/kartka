import 'dart:async';

/// Emits `combine(a, b)` whenever either stream emits, once both have
/// emitted at least once. Errors from either are forwarded; the result is
/// done when both inputs are done. Cancelling cancels both subscriptions.
Stream<R> combineLatest2<A, B, R>(
  Stream<A> a,
  Stream<B> b,
  R Function(A a, B b) combine,
) {
  late StreamController<R> out;
  StreamSubscription<A>? subA;
  StreamSubscription<B>? subB;
  A? lastA;
  B? lastB;
  var hasA = false;
  var hasB = false;
  var open = 2;

  void emit() {
    if (hasA && hasB) out.add(combine(lastA as A, lastB as B));
  }

  void done() {
    if (--open == 0) unawaited(out.close());
  }

  out = StreamController<R>(
    onListen: () {
      subA = a.listen(
        (v) {
          lastA = v;
          hasA = true;
          emit();
        },
        onError: out.addError,
        onDone: done,
      );
      subB = b.listen(
        (v) {
          lastB = v;
          hasB = true;
          emit();
        },
        onError: out.addError,
        onDone: done,
      );
    },
    onCancel: () async {
      await subA?.cancel();
      await subB?.cancel();
    },
  );
  return out.stream;
}
