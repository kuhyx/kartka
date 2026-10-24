/// Last-writer-wins helpers shared by the local repositories.
///
/// The rule matches the sync layer (contracts §4): the record with the later
/// timestamp wins; on equal timestamps the greater tie string wins. A total
/// order makes the merge commutative, associative and idempotent, so two
/// devices converge whatever order their writes arrive in.
library;

/// Returns the winner of [a] and [b] under LWW.
///
/// [at] reads a record's timestamp and [tie] gives a deterministic
/// tie-breaker (for example a canonical JSON encoding of the record).
T lwwMerge<T>(
  T a,
  T b, {
  required DateTime Function(T) at,
  required String Function(T) tie,
}) {
  final byTime = at(a).compareTo(at(b));
  if (byTime != 0) return byTime > 0 ? a : b;
  return tie(a).compareTo(tie(b)) >= 0 ? a : b;
}

/// A timestamp for a local write that must supersede [current].
///
/// Uses [now] unless the clock lags the stored record (clock skew between
/// devices), in which case it steps one millisecond past [current].
DateTime nextStamp(DateTime now, DateTime? current) {
  if (current == null || now.isAfter(current)) return now;
  return current.add(const Duration(milliseconds: 1));
}
