import 'dart:async';

import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:kartka/core/net/network_errors.dart';
import 'package:kartka/source_health/feed/source_health_feed.dart';
import 'package:kartka/source_health/model/source_health_meta.dart';
import 'package:kartka/source_health/model/source_health_record.dart';

/// The Sources tab's view of a [SourceHealthFeed]: a ranking read error
/// (the tab's error screen) is logged as `health.read`, then passed on; an
/// offline one (`isEnvironmentError`) is only passed on.
///
/// Only the tab gets this wrapper; the badge lookup reads the plain feed,
/// whose failures nobody sees. Meta errors only cost the header its run
/// totals, so they are not reported.
class ReportingHealthFeed implements SourceHealthFeed {
  /// Reports [inner]'s ranking errors into [log].
  const new(this.inner, this.log);

  /// The feed shown.
  final SourceHealthFeed inner;

  /// Where read errors go.
  final DiagnosticsLog log;

  /// An offline read after a ranking was shown is dropped, so the tab keeps
  /// that ranking until a later poll (online again) replaces it.
  @override
  Stream<List<SourceHealthRecord>> watch() {
    var shown = false;
    return inner.watch().transform(
      StreamTransformer.fromHandlers(
        handleData: (records, sink) {
          shown = true;
          sink.add(records);
        },
        handleError: (error, stack, sink) {
          final offline = isEnvironmentError(error);
          if (offline && shown) return;
          if (!offline) {
            ErrorReporter.of(log).report('health.read', error, stack: stack);
          }
          sink.addError(error, stack);
        },
      ),
    );
  }

  @override
  Stream<SourceHealthMeta?> watchMeta() => inner.watchMeta();
}
