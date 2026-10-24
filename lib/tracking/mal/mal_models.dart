/// MyAnimeList API v2 manga shapes.
library;

/// The user's list entry (`my_list_status`).
class MalListStatus {
  /// Creates a list entry.
  const new({required this.status, required this.chaptersRead, this.score});

  /// Parses `my_list_status` (or a PATCH response).
  factory fromJson(Map<String, Object?> json) {
    final status = json['status'];
    final read = json['num_chapters_read'];
    final score = json['score'];
    if (status is! String || read is! int) {
      throw const FormatException('malformed my_list_status');
    }
    return MalListStatus(
      status: status,
      chaptersRead: read,
      score: score is int && score > 0 ? score : null,
    );
  }

  /// `reading`, `completed`, `on_hold`, `dropped` or `plan_to_read`.
  final String status;

  /// `num_chapters_read`.
  final int chaptersRead;

  /// Score 1..10, `null` when unscored (MAL sends 0).
  final int? score;

  @override
  bool operator ==(Object other) =>
      other is MalListStatus &&
      other.status == status &&
      other.chaptersRead == chaptersRead &&
      other.score == score;

  @override
  int get hashCode => Object.hash(status, chaptersRead, score);

  @override
  String toString() => 'MalListStatus($status, $chaptersRead)';
}

/// One manga as returned by `/manga` or `/manga/{id}`.
class MalManga {
  /// Creates a manga.
  const new({
    required this.id,
    required this.title,
    this.coverUrl,
    this.totalChapters,
    this.listStatus,
  });

  /// Parses a manga node.
  factory fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final title = json['title'];
    if (id is! int || title is! String) {
      throw const FormatException('malformed MAL manga');
    }
    final picture = json['main_picture'];
    final chapters = json['num_chapters'];
    final status = json['my_list_status'];
    return MalManga(
      id: id,
      title: title,
      coverUrl: picture is Map<String, Object?>
          ? (picture['medium'] ?? picture['large']) as String?
          : null,
      totalChapters: chapters is int && chapters > 0 ? chapters : null,
      listStatus: status is Map<String, Object?>
          ? MalListStatus.fromJson(status)
          : null,
    );
  }

  /// MAL manga id.
  final int id;

  /// Main title.
  final String title;

  /// Cover image URL.
  final String? coverUrl;

  /// Total chapters, `null` while unknown (MAL sends 0).
  final int? totalChapters;

  /// The user's entry, `null` when the manga is not on their list.
  final MalListStatus? listStatus;
}
