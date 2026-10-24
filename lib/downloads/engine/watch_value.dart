import 'dart:async';

/// A stream that emits [read]() once [ready] completes and again after
/// every event on [changes]. Cancelling before [ready] is safe.
Stream<T> watchValue<T>(
  Future<void> ready,
  Stream<void> changes,
  T Function() read,
) {
  late final StreamController<T> out;
  StreamSubscription<void>? sub;
  var cancelled = false;
  out = StreamController<T>(
    onListen: () async {
      await ready;
      if (cancelled) return;
      out.add(read());
      sub = changes.listen((_) => out.add(read()));
    },
    onCancel: () {
      cancelled = true;
      return sub?.cancel();
    },
  );
  return out.stream;
}
