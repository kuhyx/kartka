/// Natural ("human") ordering for page and chapter file names.
///
/// `page2` sorts before `page10`. Whole paths are compared, so `ch1/p2`
/// precedes `ch10/p1`. Comparison is case-insensitive. Ties (case or leading
/// zeros) fall back to plain string order, so the order stays total and
/// deterministic.
library;

const int _zero = 0x30;
const int _nine = 0x39;

/// Compares [a] and [b] naturally. Returns <0, 0 or >0 like [Comparable].
int naturalCompare(String a, String b) {
  final primary = _compareFolded(a.toLowerCase(), b.toLowerCase());
  return primary != 0 ? primary : a.compareTo(b);
}

/// Returns a new list with [items] in natural order of [key] (identity
/// when [key] is omitted and the items are strings).
List<T> naturalSortedBy<T>(Iterable<T> items, String Function(T) key) =>
    items.toList()..sort((x, y) => naturalCompare(key(x), key(y)));

/// Returns a new list with [names] in natural order.
List<String> naturalSorted(Iterable<String> names) =>
    naturalSortedBy(names, (n) => n);

bool _isDigit(int c) => c >= _zero && c <= _nine;

/// Walks both strings; runs of digits compare by numeric value, any other
/// code unit compares by value. A digit run therefore sits between the code
/// units below '0' and above '9', which keeps the order transitive.
int _compareFolded(String x, String y) {
  var i = 0;
  var j = 0;
  while (i < x.length && j < y.length) {
    final cx = x.codeUnitAt(i);
    final cy = y.codeUnitAt(j);
    if (_isDigit(cx) && _isDigit(cy)) {
      final ei = _runEnd(x, i);
      final ej = _runEnd(y, j);
      final byValue = _compareDigits(x.substring(i, ei), y.substring(j, ej));
      if (byValue != 0) return byValue;
      i = ei;
      j = ej;
    } else if (cx != cy) {
      return cx < cy ? -1 : 1;
    } else {
      i++;
      j++;
    }
  }
  return ((x.length - i) - (y.length - j)).sign;
}

int _runEnd(String s, int start) {
  var end = start;
  while (end < s.length && _isDigit(s.codeUnitAt(end))) {
    end++;
  }
  return end;
}

/// Compares two digit strings by value without parsing, so arbitrarily long
/// runs cannot overflow.
int _compareDigits(String a, String b) {
  final x = _stripZeros(a);
  final y = _stripZeros(b);
  if (x.length != y.length) return x.length < y.length ? -1 : 1;
  return x.compareTo(y).sign;
}

String _stripZeros(String digits) {
  var k = 0;
  while (k < digits.length - 1 && digits.codeUnitAt(k) == _zero) {
    k++;
  }
  return digits.substring(k);
}
