import 'package:kartka/tracking/common/tracker.dart';

/// The AniList list status to send with a push of [progress], or `null` to
/// leave the status as it is.
///
/// Reading moves PLANNING / PAUSED / DROPPED (or a missing entry) to
/// CURRENT, and reaching the known total completes the entry. COMPLETED and
/// REPEATING are never touched, so a push never downgrades a status.
String? statusAfterPush({
  required TrackStatus? current,
  required int progress,
}) {
  final total = current?.totalChapters;
  final finished = total != null && total > 0 && progress >= total;
  final status = current?.status;
  if (status == 'COMPLETED' || status == 'REPEATING') return null;
  if (finished) return 'COMPLETED';
  if (status == 'CURRENT') return null;
  return 'CURRENT';
}
