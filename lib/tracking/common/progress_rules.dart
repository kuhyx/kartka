/// Monotonic progress rules shared by every tracker: nothing here can lower
/// a chapter count, locally or remotely.
library;

import 'dart:math' as math;

/// Whole chapters read for a local `chapterNumber`; 10.5 counts as 10.
/// Returns `null` when the number carries no usable count.
int? chaptersReadFrom(double? chapterNumber) {
  if (chapterNumber == null || !chapterNumber.isFinite || chapterNumber < 0) {
    return null;
  }
  return chapterNumber.floor();
}

/// The count to store remotely: never below what the remote already has.
int pushTarget({required int local, required int remote}) =>
    math.max(local, remote);

/// Whether the remote count must move up to reach [local].
bool needsPush({required int local, required int remote}) => local > remote;

/// Whether a push of [local] was already done (skips a fetch round-trip).
bool alreadyPushed({required int local, required int? lastPushed}) =>
    lastPushed != null && lastPushed >= local;

/// Whether remote progress should be pulled forward into local.
bool needsPull({required int? local, required int remote}) =>
    remote > 0 && (local == null || remote > local);
