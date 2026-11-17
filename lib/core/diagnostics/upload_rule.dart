import 'package:kartka/core/diagnostics/diagnostic_entry.dart';
import 'package:kartka/core/net/network_errors.dart';

/// Whether [e] goes up to `/kartka/errors` (`ErrorUploader`): failures and
/// slow waits do; the rest of `perf.*` (jank) and environment states
/// (`isEnvironmentError`: offline, server down) a screen caught stay on
/// the device. An escaped (`uncaught.*`) one is a bug, so it goes up.
///
/// Pure Dart, so `tools/agent/uploadable.dart` judges a device log by the
/// very rule the app ships.
bool isUploadedEntry(DiagnosticEntry e) =>
    e.kind == 'perf.slow' ||
    !e.kind.startsWith('perf.') &&
        (e.kind.startsWith('uncaught.') || !isEnvironmentError(e.error));
