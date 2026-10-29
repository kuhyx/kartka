/// Deep equality of decoded JSON values.
///
/// Replaces `canon(a) == canon(b)` where only "did it change?" matters: it
/// allocates nothing and stops at the first difference, while `canon`
/// sorts and re-encodes the whole tree every time (the source-health tree
/// once a minute, on the UI isolate).
library;

/// Whether [a] and [b] are the same JSON value: maps compare by key set
/// (order blind), lists element by element, scalars with `==`.
bool jsonEquals(Object? a, Object? b) {
  if (a is Map) {
    if (b is! Map || a.length != b.length) return false;
    for (final MapEntry(:key, :value) in a.entries) {
      if (!b.containsKey(key) || !jsonEquals(value, b[key])) return false;
    }
    return true;
  }
  if (a is List) {
    if (b is! List || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!jsonEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a.runtimeType == b.runtimeType && a == b;
}
