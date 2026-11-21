import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/updates/chapter_backfill.dart';
import 'package:kartka/core/updates/chapter_update_checker.dart';
import 'package:kartka/platform/memory/memory_stores.dart';

/// A checker that "stores" a list by moving [pending] facts into [stored].
class MovingChecker<F> implements ChapterUpdateChecker {
  /// Moves from [pending] into [stored] on each check.
  new(this.pending, this.stored);

  /// Facts not stored yet.
  final Map<MangaKey, F> pending;

  /// Facts the lookup answers with.
  final Map<MangaKey, F> stored;

  @override
  Future<UpdateResult> check(MangaKey key) async {
    stored[key] = pending.remove(key) as F;
    return UpdateFound(
      key,
      chapters: const [],
      added: const [],
      firstCheck: true,
    );
  }
}

/// A backfill over [checker] on memory stores, at [now].
ChapterBackfill backfillOf(ChapterUpdateChecker checker, DateTime now) =>
    ChapterBackfill(
      checker: () => checker,
      local: MemoryKeyValueStore(),
      log: DiagnosticsLog(MemoryBlobStore()),
      clock: () => now,
    );
