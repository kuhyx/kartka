/// Moments of this launch, in ms on one clock, so a slow first library
/// paint can say what it waited on (`LibraryProbe`, library.load
/// a133bbb8). Each step keeps its first moment only; the launch instance
/// is cheap enough to mark from anywhere (a map insert).
class StartupMarks {
  /// Marks read from [elapsedMs] (tests); the default starts its own clock.
  new({int Function()? elapsedMs}) : _elapsedMs = elapsedMs ?? _clock();

  static int Function() _clock() {
    final watch = Stopwatch()..start();
    return () => watch.elapsedMilliseconds;
  }

  /// This launch's marks; its clock starts at first use (`main`).
  static final StartupMarks launch = StartupMarks();

  final int Function() _elapsedMs;
  final Map<String, int> _at = {};
  final Map<String, String Function()> _notes = {};

  /// Records that [step] happened now, unless it already did.
  void mark(String step) => _at.putIfAbsent(step, _elapsedMs);

  /// Adds `name=<text()>` after the marks; [text] runs only in [describe],
  /// so a costly summary stays off the path it describes.
  void note(String name, String Function() text) =>
      _notes.putIfAbsent(name, () => text);

  /// Every step so far with its moment, in the order they happened.
  Map<String, int> get marks => Map.unmodifiable(_at);

  /// `step=ms` pairs in order, then the notes, one line.
  String describe() => [
    for (final MapEntry(:key, :value) in _at.entries) '$key=$value',
    for (final MapEntry(:key, :value) in _notes.entries) '$key=${value()}',
  ].join(' ');

  /// Milliseconds from [from] to [to], or null if either is missing.
  int? since(String from, String to) {
    final a = _at[from];
    final b = _at[to];
    return a == null || b == null ? null : b - a;
  }

  /// Of the steps that ended after [wait] was marked, the one that took
  /// the most of the wait (a step that began earlier counts from [wait]);
  /// null without [wait] or a step after it.
  ({String step, int ms})? slowestSince(String wait) {
    final start = _at[wait];
    if (start == null) return null;
    ({String step, int ms})? slowest;
    var previous = 0;
    for (final MapEntry(key: step, value: at) in _at.entries) {
      if (at > start) {
        final ms = at - (previous > start ? previous : start);
        if (slowest == null || ms > slowest.ms) slowest = (step: step, ms: ms);
      }
      previous = at;
    }
    return slowest;
  }
}
