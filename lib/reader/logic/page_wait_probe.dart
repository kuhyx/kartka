import 'dart:async';

/// Times a shown page's wait (28fffd0a): from the first time the screen
/// asks for page bytes that have not arrived until they settle. A wait of
/// [limit] or more goes to [onSlow] with the step most of it went to:
/// `queue` (waiting for its turn behind the shown page and the
/// look-aheads), `turn` (a fetch that started only at the turn: no
/// look-ahead reached the page), `open` or `advance` (the same, for the
/// page a chapter opened on or the first page past a chapter edge), `warm`
/// (joined a fetch the details screen or the Updates sheet warmed) or
/// `prefetch` (fetched well before the turn, and the host was still slower
/// than the reader).
///
/// The perf.slow report says only that a page spun; this says why.
class PageWaitProbe {
  /// A probe reading [now], reporting waits of [limit] or more.
  new({
    required this.now,
    required this.onSlow,
    this.limit = const Duration(seconds: 1),
  });

  /// The clock.
  final DateTime Function() now;

  /// Called once per slow wait with the page index, the step and the wait.
  final void Function(int index, String step, Duration waited) onSlow;

  /// The shortest wait reported.
  final Duration limit;

  /// How long before the ask a fetch must have started to count as a
  /// prefetch: a pager turn starts the shown page's fetch just before the
  /// screen asks for it, which is not one.
  static const prefetchLead = Duration(milliseconds: 250);

  final Map<int, DateTime> _asked = {};
  final Map<int, ({DateTime at, bool warm})> _started = {};

  /// The fetch of page [index] started (again, after a failure): now, or
  /// [at] when it joined a fetch already running ([warm]: a warm's).
  void started(int index, {DateTime? at, bool warm = false}) =>
      _started[index] = (at: at ?? now(), warm: warm);

  /// The screen asked for page [index], whose bytes are [bytes] and have
  /// not arrived; an ask while it is already timed joins that wait. [edge]
  /// (`open`, `advance`) names a fetch that started only at the ask.
  void asked(int index, Future<Object?> bytes, {String? edge}) {
    if (_asked.containsKey(index)) return;
    final at = now();
    _asked[index] = at;
    void settled() {
      _asked.remove(index);
      final waited = now().difference(at);
      if (waited < limit) return;
      final step = _step(_started[index], at, waited);
      onSlow(index, step == 'turn' ? edge ?? step : step, waited);
    }

    unawaited(
      bytes.then<void>((_) => settled(), onError: (Object _) => settled()),
    );
  }

  /// What a wait of [waited] from [asked] went to, for a fetch that
  /// [began] then (null: never started).
  static String _step(
    ({DateTime at, bool warm})? began,
    DateTime asked,
    Duration waited,
  ) {
    if (began == null) return 'queue';
    final at = began.at;
    if (at.isAfter(asked)) {
      return at.difference(asked) * 2 > waited ? 'queue' : 'turn';
    }
    if (began.warm) return 'warm';
    return asked.difference(at) < prefetchLead ? 'turn' : 'prefetch';
  }

  /// The image host of [imageUrl] cut to its last two labels (an IP
  /// whole), or `storage` for a downloaded page. A report's text, and so
  /// its board ticket, stays one per step and source: MangaDex hands out a
  /// different `<node>.mangadex.network` per chapter.
  static String domain(String imageUrl) {
    final host = Uri.tryParse(imageUrl)?.host ?? '';
    if (host.isEmpty) return 'storage';
    if (RegExp(r'^[\d.]+$').hasMatch(host)) return host;
    final labels = host.split('.');
    return labels.skip(labels.length < 2 ? 0 : labels.length - 2).join('.');
  }
}
