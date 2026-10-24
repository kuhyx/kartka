import 'package:flutter/foundation.dart';
import 'package:kartka/library/data/mark.dart';

/// Every read [Mark] of one manga, stored as ONE row so a bulk import
/// (thousands of chapters) is one store write, not one per chapter.
@immutable
class MarkSet {
  /// Creates a set for [key].
  const new({required this.key, this.marks = const {}});

  /// Decodes the shape written by [toJson].
  factory fromJson(Map<String, Object?> json) {
    final list = json['marks']! as List<Object?>;
    final marks = [
      for (final m in list) Mark.fromJson(m! as Map<String, Object?>),
    ];
    return MarkSet(
      key: json['key']! as String,
      marks: {for (final m in marks) m.target: m},
    );
  }

  /// The manga key.
  final String key;

  /// Chapter url to its mark.
  final Map<String, Mark> marks;

  /// Sets every url in [targets] to [on] at [now]; `null` when nothing
  /// changes.
  static MarkSet? apply(
    MarkSet? current,
    String key,
    Iterable<String> targets, {
    required bool on,
    required DateTime now,
  }) {
    final next = {...?current?.marks};
    var changed = false;
    for (final t in targets) {
      final m = flip(next[t], key, t, on: on, now: now);
      if (m != null) {
        next[t] = m;
        changed = true;
      }
    }
    return changed ? MarkSet(key: key, marks: next) : null;
  }

  /// JSON shape: the marks as a list (urls are not safe map keys in RTDB).
  Map<String, Object?> toJson() => {
    'key': key,
    'marks': [for (final m in marks.values) m.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      other is MarkSet && other.key == key && mapEquals(other.marks, marks);

  @override
  int get hashCode => Object.hash(key, Object.hashAllUnordered(marks.values));
}
