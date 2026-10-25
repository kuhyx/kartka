import 'dart:async';

/// The first event of [stream], cancelling without waiting for the cancel.
///
/// `Stream.first` completes only after the subscription's cancel future
/// does; a repository stream's teardown can stall under a widget test's
/// fake clock, and nothing here needs to wait for it.
Future<T> firstValue<T>(Stream<T> stream) {
  final done = Completer<T>();
  StreamSubscription<T>? sub;
  var cancelOnListen = false;
  void stop() {
    // A synchronous stream can emit inside `listen`, before `sub` is set.
    if (sub case final s?) {
      unawaited(s.cancel());
    } else {
      cancelOnListen = true;
    }
  }

  sub = stream.listen(
    (value) {
      if (done.isCompleted) return;
      done.complete(value);
      stop();
    },
    onError: (Object e, StackTrace s) {
      if (done.isCompleted) return;
      done.completeError(e, s);
      stop();
    },
    onDone: () {
      if (!done.isCompleted) done.completeError(StateError('No element'));
    },
  );
  if (cancelOnListen) unawaited(sub.cancel());
  return done.future;
}
