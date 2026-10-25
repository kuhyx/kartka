import 'package:kartka/app/feature.dart';
import 'package:kartka/source_health/feed/rtdb_feed.dart';
import 'package:kartka/source_health/feed/source_health_feed.dart';
import 'package:kartka/source_health/model/source_health_meta.dart';
import 'package:kartka/source_health/model/source_health_record.dart';
import 'package:kartka/source_health/source_health_lookup_impl.dart';
import 'package:kartka/source_health/ui/sources_tab.dart';
import 'package:kartka/sync/rtdb_reader.dart';

/// The source-health part: fills the Sources tab and supplies Browse's
/// `SourceHealthLookup`, both fed from RTDB `/kartka/source_health`.
KartkaFeature sourceHealthFeature(KartkaEnv env) {
  final feed = _RegistryFeed(() => env.registry.maybe<RtdbReader>());
  return KartkaFeature(
    id: 'source-health',
    tabs: {KartkaTab.sources: (_) => SourcesTab(feed: feed)},
    services: [FeedSourceHealthLookup(feed)],
  );
}

/// Resolves the sync part's [RtdbReader] lazily: the registry is only
/// complete after every factory has run.
class _RegistryFeed implements SourceHealthFeed {
  new(this._reader);

  final RtdbReader? Function() _reader;

  @override
  Stream<List<SourceHealthRecord>> watch() {
    final reader = _reader();
    if (reader == null) {
      return Stream.error(
        StateError('Source health is read through sync, which is not set up.'),
      );
    }
    return RtdbSourceHealthFeed(reader).watch();
  }

  /// Without sync the records stream already shows the error; the header
  /// just falls back to counting records.
  @override
  Stream<SourceHealthMeta?> watchMeta() {
    final reader = _reader();
    return reader == null
        ? Stream.value(null)
        : RtdbSourceHealthFeed(reader).watchMeta();
  }
}
