/// Kartka's wiring of the shared app-errors reporter (crdt_sync_flutter,
/// kuhyx/utils `DOCS-app-errors.md`): uncaught errors, slow waits
/// (`WaitWatch`) and the upload are shared; the device log
/// ([DiagnosticsLog]) and its environment filter stay kartka's.
library;

import 'dart:async';

import 'package:crdt_sync_flutter/crdt_sync_flutter.dart';
import 'package:kartka/app/screen_observer.dart';
import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:kartka/core/diagnostics/upload_rule.dart';

/// Kartka's identity in its reports; [build] and [version] default to the
/// release build's `--dart-define`s (0 / absent: the installed versionCode
/// is read instead).
AppErrorsConfig kartkaErrorsConfig({
  int build = const int.fromEnvironment('APP_BUILD'),
  String version = const String.fromEnvironment('APP_VERSION'),
}) => AppErrorsConfig(
  app: 'kartka',
  repo: 'kuhyx/kartka',
  package: 'kartka',
  build: build,
  version: version.isEmpty ? null : version,
);

/// Queues every entry [log] gains that is a bug (`isUploadedEntry`) for
/// [errors]' upload. Offline and server-down states stay on the device;
/// `perf.*` and `uncaught.*` are the shared hooks' and `WaitWatch`'s own,
/// so they are not queued twice.
StreamSubscription<DiagnosticEntry> bridgeDiagnostics(
  DiagnosticsLog log,
  AppErrors errors,
) => log.appended.listen((e) {
  if (e.kind.startsWith('perf.') || e.kind.startsWith('uncaught.')) return;
  if (!isUploadedEntry(e)) return;
  errors.queue.add(
    ErrorEntry(
      at: e.at,
      kind: e.kind,
      error: e.error,
      stack: e.stack,
      route: e.route,
    ),
  );
});

/// Stamps the go_router pattern on top into [errors], so reports and slow
/// waits name `/manga/:sourceId/:mangaUrl`, never a location. (A tab switch
/// pushes no route, so a Navigator observer alone would miss it.)
class ErrorRouteObserver implements ScreenObserver {
  /// Stamps into [errors].
  const new(this.errors);

  /// The reporting stamped.
  final AppErrors errors;

  @override
  void screenChanged(String pattern) => errors.reporter.route = pattern;
}
