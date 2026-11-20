import 'package:kartka/core/diagnostics/diagnostic_entry.dart';
import 'package:kartka/core/net/network_errors.dart';

/// Kinds that record what the app did, not a fault: they stay on the
/// device (`library.autoshelve`: how many entries auto-shelving moved).
const Set<String> deviceOnlyKinds = {'library.autoshelve'};

/// Whether [e] goes up to `/kartka/errors` (`ErrorUploader`): failures and
/// slow waits do; the rest of `perf.*` (jank), [deviceOnlyKinds] and
/// environment states (`isEnvironmentError`: offline, server down) a screen
/// caught stay on the device. An escaped (`uncaught.*`) one is a bug, so it
/// goes up.
///
/// Pure Dart, so `tools/agent/uploadable.dart` judges a device log by the
/// very rule the app ships.
bool isUploadedEntry(DiagnosticEntry e) =>
    e.kind == 'perf.slow' ||
    !e.kind.startsWith('perf.') &&
        !deviceOnlyKinds.contains(e.kind) &&
        (e.kind.startsWith('uncaught.') || !isEnvironmentError(e.error));
