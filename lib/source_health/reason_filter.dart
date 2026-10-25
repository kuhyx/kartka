/// The Sources screen's reason filter: why a source was cut (or, on a kept
/// source, what it was warned about). The scoring profile's cut switches
/// are keyed by these too.
library;

import 'package:kartka/source_health/model/source_health_record.dart';

/// A reason a record can be filtered by.
enum HealthReason {
  /// Blocked by a challenge other than a browser-engine need.
  blocking('Blocking'),

  /// A higher-ranked source has nearly all of its titles.
  subset('Subset'),

  /// Too few reference titles.
  coverage('Low coverage'),

  /// Answered too few uptime probes.
  uptime('Low uptime'),

  /// Its extension needs a browser engine (flagged; cut only if the active
  /// scoring profile says so).
  browserEngine('Browser engine'),

  /// No sampled chapter had all its pages load (`pagesLoad.ratio` is 0).
  pagesNeverLoad('Pages never load');

  new(this.label);

  /// Chip label.
  final String label;
}

/// Every [HealthReason] that applies to [r], from its cut-reason codes,
/// `subsetOf`, blocking kinds and flags.
Set<HealthReason> reasonsOf(SourceHealthRecord r) {
  bool code(String prefix) => r.cutReasons.any((c) => c.startsWith(prefix));
  final kinds = r.blocking?.kinds ?? const <String>[];
  return {
    if (code('blocking') || kinds.any((k) => k != 'webview'))
      HealthReason.blocking,
    if (code('subset') || r.subsetOf != null) HealthReason.subset,
    if (code('coverage')) HealthReason.coverage,
    if (code('uptime')) HealthReason.uptime,
    if (r.needsBrowserEngine || kinds.contains('webview'))
      HealthReason.browserEngine,
    if (r.pagesLoad?.ratio == 0) HealthReason.pagesNeverLoad,
  };
}
