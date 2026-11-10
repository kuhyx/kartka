import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/redact.dart';

/// What a manga-detail refresh (pull-to-refresh or the app-bar action) did.
sealed class RefreshOutcome {
  const new();
}

/// The refresh failed with [error]; the screen keeps what it showed.
final class RefreshFailed extends RefreshOutcome {
  /// Creates the outcome for [error].
  const new(this.error);

  /// The failure.
  final Object error;
}

/// The refresh worked; [added] are the chapters not listed before it,
/// oldest first.
final class RefreshSucceeded extends RefreshOutcome {
  /// Creates the outcome listing [added].
  const new(this.added);

  /// Chapters new since the previous list.
  final List<ChapterInfo> added;
}

/// Most chapter numbers a refresh snackbar lists before "+N more".
const int refreshListedChapters = 5;

/// The snackbar text for [outcome]: `Refresh failed: <message>` (URL
/// secrets redacted), `No new chapters`, or `3 new: ch 101, 102, 103`
/// (at most [refreshListedChapters] numbers, then ` +N more`).
String refreshMessage(RefreshOutcome outcome) => switch (outcome) {
  RefreshFailed(:final error) =>
    'Refresh failed: ${redactUrlQueries('$error')}',
  RefreshSucceeded(added: []) => 'No new chapters',
  RefreshSucceeded(:final added) => _newChapters(added),
};

String _newChapters(List<ChapterInfo> added) {
  final listed = added.take(refreshListedChapters).map(_label).join(', ');
  final more = added.length - refreshListedChapters;
  return '${added.length} new: ch $listed${more > 0 ? ' +$more more' : ''}';
}

/// The word-free painted form of [added]: at most [refreshListedChapters]
/// chapter numbers, then `+N` for the rest (`101, 102 +3`).
String newChapterNumbers(List<ChapterInfo> added) {
  final listed = added.take(refreshListedChapters).map(_label).join(', ');
  final more = added.length - refreshListedChapters;
  return more > 0 ? '$listed +$more' : listed;
}

String _label(ChapterInfo c) => switch (c.number) {
  null => c.name,
  final n when n == n.truncateToDouble() => '${n.toInt()}',
  final n => '$n',
};

/// [text] with every URL and query string removed, for diagnostics entries
/// (which must carry neither): http(s) URLs become `<url>`, and any other
/// `?query` (a relative source path) becomes `?<redacted>`.
String stripUrls(String text) => text
    .replaceAll(
      RegExp(r'''https?://[^\s"'<>]*''', caseSensitive: false),
      '<url>',
    )
    .replaceAll(RegExp(r'''\?[^\s"'<>]+'''), '?<redacted>');
