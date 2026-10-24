import 'package:kartka/core/models/manga_key.dart';

/// A library entry bound to one remote tracker entry (contracts §4
/// `trackers/<mangaKeyHash>/<service>`).
class TrackBinding {
  /// Creates a binding.
  const new({
    required this.key,
    required this.service,
    required this.remoteId,
    this.lastPushedChapter,
  });

  /// Decodes [toJson] output.
  factory fromJson(Map<String, Object?> json) => TrackBinding(
    key: json['key']! as String,
    service: json['service']! as String,
    remoteId: json['remoteId']! as String,
    lastPushedChapter: (json['lastPushedChapter'] as num?)?.toInt(),
  );

  /// The bound library entry.
  final MangaKey key;

  /// Tracker id (`anilist`, `mal`).
  final String service;

  /// Remote media id.
  final String remoteId;

  /// Highest chapter count known to be on the remote, `null` before the
  /// first push or pull. Only ever grows (merge rule: max).
  final int? lastPushedChapter;

  /// A copy with [lastPushedChapter] replaced.
  TrackBinding copyWith({int? lastPushedChapter}) => TrackBinding(
    key: key,
    service: service,
    remoteId: remoteId,
    lastPushedChapter: lastPushedChapter ?? this.lastPushedChapter,
  );

  /// JSON for storage and sync.
  Map<String, Object?> toJson() => {
    'key': key,
    'service': service,
    'remoteId': remoteId,
    'lastPushedChapter': ?lastPushedChapter,
  };

  @override
  bool operator ==(Object other) =>
      other is TrackBinding &&
      other.key == key &&
      other.service == service &&
      other.remoteId == remoteId &&
      other.lastPushedChapter == lastPushedChapter;

  @override
  int get hashCode => Object.hash(key, service, remoteId, lastPushedChapter);

  @override
  String toString() => 'TrackBinding($key, $service:$remoteId)';
}
