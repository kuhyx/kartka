import 'package:kartka/core/models/models.dart';

/// "Does this manga have new chapters?" for one manga, without any UI.
///
/// Fetches the manga's chapter list from its source, diffs it against the
/// list kartka stored for it (by chapter url), persists the fetched list as
/// the new baseline and returns the chapters that were not known before.
///
/// Owner: browse (`StoreChapterUpdateChecker`, over its chapter cache),
/// registered in `KartkaFeature.services`, so any part reads it with
/// `registry.maybe<ChapterUpdateChecker>()`. The manga detail screen's
/// pull-to-refresh uses the same instance.
///
/// Contract:
/// - [check] never throws: a failure (network, parse, challenge, unknown
///   source) is an [UpdateFailed] and the stored list is left as it was.
/// - Nothing stored yet (never fetched on this device): the fetch becomes
///   the baseline, [UpdateFound.firstCheck] is true and
///   [UpdateFound.added] is empty, so a first run never reports a whole
///   back catalogue as new.
/// - Concurrency-safe per manga: concurrent [check]s of one key share a
///   single fetch and complete with the identical result. Different keys run
///   independently; callers checking a whole library bound the parallelism
///   themselves.
/// - Only [check] reports new chapters to its caller. Opening a detail page
///   re-fetches and stores the list directly (and tracking's chapter
///   resolver stores a first one), moving the baseline, so an "update all"
///   run right after finds nothing new for that manga. Every such store
///   that adds chapters is still told to each `ChapterAdditionSink` (the
///   updates feed), so the feed misses none whichever path fetched.
/// - Callers log failures (the detail screen writes `details.refresh` to the
///   diagnostics log); the checker itself logs nothing, so a caller with its
///   own entry kind never logs twice.
abstract interface class ChapterUpdateChecker {
  /// Checks the manga [key] (`mangaKeyOf(sourceId, mangaUrl)`); it does not
  /// need to be in the library.
  Future<UpdateResult> check(MangaKey key);
}

/// What one [ChapterUpdateChecker.check] found.
sealed class UpdateResult {
  const new(this.key);

  /// The checked manga.
  final MangaKey key;
}

/// The fetch worked and is now the stored list.
final class UpdateFound extends UpdateResult {
  /// Creates the result for [key].
  const new(
    super.key, {
    required this.chapters,
    required this.added,
    required this.firstCheck,
  });

  /// The whole fetched list, in source order (normally newest first).
  final List<ChapterInfo> chapters;

  /// Chapters not in the previously stored list, oldest first.
  final List<ChapterInfo> added;

  /// Whether nothing was stored before (then [added] is empty).
  final bool firstCheck;
}

/// The fetch failed with [error]; nothing was stored.
final class UpdateFailed extends UpdateResult {
  /// Creates the result for [key].
  const new(super.key, this.error, [this.stack]);

  /// The failure, unredacted: redact before showing or logging it.
  final Object error;

  /// Where it was thrown, when known.
  final StackTrace? stack;
}
