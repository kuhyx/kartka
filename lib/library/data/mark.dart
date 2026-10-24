import 'package:flutter/foundation.dart';
import 'package:kartka/library/data/lww.dart';

/// A last-writer-wins boolean about one manga and one target: category
/// membership (target = category id) or a chapter read mark (target =
/// chapter url). `on: false` is a tombstone, never a delete (contracts §4).
@immutable
class Mark {
  /// Creates a mark.
  const new({
    required this.key,
    required this.target,
    required this.on,
    required this.at,
  });

  /// Decodes the shape written by [toJson].
  factory fromJson(Map<String, Object?> json) => Mark(
    key: json['key']! as String,
    target: json['target']! as String,
    on: json['on']! as bool,
    at: DateTime.fromMillisecondsSinceEpoch(json['at']! as int, isUtc: true),
  );

  /// The manga key.
  final String key;

  /// Category id or chapter url.
  final String target;

  /// Member / read.
  final bool on;

  /// LWW clock.
  final DateTime at;

  /// JSON shape; [at] in epoch milliseconds like the RTDB record.
  Map<String, Object?> toJson() => {
    'key': key,
    'target': target,
    'on': on,
    'at': at.millisecondsSinceEpoch,
  };

  @override
  bool operator ==(Object other) =>
      other is Mark &&
      other.key == key &&
      other.target == target &&
      other.on == on &&
      other.at.isAtSameMomentAs(at);

  @override
  int get hashCode => Object.hash(key, target, on, at.millisecondsSinceEpoch);
}

/// The [Mark] that sets [key]/[target] to [on] at [now], or `null` when
/// [current] already says so (an absent mark counts as off).
Mark? flip(
  Mark? current,
  String key,
  String target, {
  required bool on,
  required DateTime now,
}) {
  if ((current?.on ?? false) == on) return null;
  return Mark(
    key: key,
    target: target,
    on: on,
    at: nextStamp(_wholeMs(now), current?.at),
  );
}

// Marks persist epoch milliseconds, so stamps are truncated before use.
DateTime _wholeMs(DateTime t) =>
    DateTime.fromMillisecondsSinceEpoch(t.millisecondsSinceEpoch, isUtc: true);
