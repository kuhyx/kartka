import 'package:kartka/core/models/json_fields.dart';

/// Lifecycle of one chapter download.
enum DownloadStatus {
  /// Not downloaded and not queued.
  none,

  /// Waiting in the queue.
  queued,

  /// Pages are being fetched.
  downloading,

  /// Every page is stored offline.
  done,

  /// Gave up; see [DownloadState.error].
  failed,
}

/// Progress of one chapter download (`DownloadRepository.watch`, §8).
///
/// Shape defined by foundation; §8 names the type without fields.
class DownloadState {
  /// Creates a state.
  const new({
    required this.status,
    this.pagesDone = 0,
    this.pagesTotal = 0,
    this.error,
  });

  /// Decodes the shape written by [toJson].
  factory fromJson(Map<String, Object?> json) => DownloadState(
    status: DownloadStatus.values.byName(readString(json, 'status')),
    pagesDone: readInt(json, 'pagesDone'),
    pagesTotal: readInt(json, 'pagesTotal'),
    error: readOptString(json, 'error'),
  );

  /// The state of a chapter nobody asked to download.
  static const none = DownloadState(status: DownloadStatus.none);

  /// Where the download is.
  final DownloadStatus status;

  /// Pages stored so far.
  final int pagesDone;

  /// Pages in the chapter; 0 until the page list is known.
  final int pagesTotal;

  /// Why it failed, when [status] is [DownloadStatus.failed].
  final String? error;

  /// Fraction complete in `[0, 1]`; 0 while [pagesTotal] is unknown.
  double get fraction =>
      pagesTotal == 0 ? 0 : (pagesDone / pagesTotal).clamp(0, 1).toDouble();

  /// JSON shape; [status] by enum name.
  Map<String, Object?> toJson() => {
    'status': status.name,
    'pagesDone': pagesDone,
    'pagesTotal': pagesTotal,
    'error': error,
  };

  @override
  bool operator ==(Object other) =>
      other is DownloadState &&
      other.status == status &&
      other.pagesDone == pagesDone &&
      other.pagesTotal == pagesTotal &&
      other.error == error;

  @override
  int get hashCode => Object.hash(status, pagesDone, pagesTotal, error);

  @override
  String toString() => 'DownloadState(${status.name} $pagesDone/$pagesTotal)';
}
