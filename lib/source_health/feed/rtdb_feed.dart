import 'package:kartka/source_health/feed/source_health_feed.dart';
import 'package:kartka/source_health/model/source_health_record.dart';
import 'package:kartka/sync/rtdb_reader.dart';

/// A [SourceHealthFeed] over RTDB `/kartka/source_health` (§4), which only
/// the evaluator writes. Read-only; the reader does the polling.
class RtdbSourceHealthFeed implements SourceHealthFeed {
  /// Creates a feed reading through the sync part's [RtdbReader].
  new(this._reader);

  /// The subtree, relative to the `/kartka` root as [RtdbReader] expects.
  static const String path = 'source_health';

  final RtdbReader _reader;

  @override
  Stream<List<SourceHealthRecord>> watch() =>
      _reader.watch(path).map(parseHealthCollection);
}
