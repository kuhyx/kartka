import 'dart:async';

/// Times a shown page's wait (28fffd0a): from the first time the screen
/// asks for page bytes that have not arrived until they settle. A wait of
/// [limit] or more goes to [onSlow] with the step most of it went to:
/// `queue` (waiting for its turn behind the shown page and the
/// look-aheads), `fetch after turn` (a fetch that started only at the
/// turn: no look-ahead reached the page) or `prefetch` (fetched well before
/// the turn, and the host was still slower than the reader).
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
  final Map<int, DateTime> _started = {};

  /// The fetch of page [index] started (again, after a failure).
  void started(int index) => _started[index] = now();

  /// The screen asked for page [index], whose bytes are [bytes] and have
  /// not arrived; an ask while it is already timed joins that wait.
  void asked(int index, Future<Object?> bytes) {
    if (_asked.containsKey(index)) return;
    final at = now();
    _asked[index] = at;
    void settled() {
      _asked.remove(index);
      final waited = now().difference(at);
      if (waited < limit) return;
      onSlow(index, _step(_started[index], at, waited), waited);
    }

    unawaited(
      bytes.then<void>((_) => settled(), onError: (Object _) => settled()),
    );
  }

  /// What a wait of [waited] from [asked] went to, for a fetch that
  /// [began] then (null: never started).
  static String _step(DateTime? began, DateTime asked, Duration waited) {
    if (began == null) return 'queue';
    if (began.isAfter(asked)) {
      return began.difference(asked) * 2 > waited
          ? 'queue'
          : 'fetch after turn';
    }
    return asked.difference(began) < prefetchLead
        ? 'fetch after turn'
        : 'prefetch';
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
