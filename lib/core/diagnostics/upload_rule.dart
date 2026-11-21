import 'package:kartka/core/diagnostics/diagnostic_entry.dart';
import 'package:kartka/core/net/network_errors.dart';

/// Kinds that record what the app did, not a fault: they stay on the
/// device (`library.autoshelve`: how many entries auto-shelving moved;
/// `library.dedupe`: how many duplicates were merged; `library.backfill`: a
/// chapter list fetch for auto-shelving that failed).
const Set<String> deviceOnlyKinds = {
  'library.autoshelve',
  'library.dedupe',
  'library.backfill',
};

/// Kind of the extension auto-update's summary line
/// (`lib/source_health/install/extension_autoupdate.dart`).
const String autoUpdateKind = 'sources.autoupdate';

/// The word an auto-update summary carries when some update failed.
const String autoUpdateFailed = 'failed';

/// Whether [e] goes up to `/kartka/errors` (`ErrorUploader`): failures and
/// slow waits do; the rest of `perf.*` (jank), [deviceOnlyKinds],
/// environment states (`isEnvironmentError`: offline, server down) a screen
/// caught, and an auto-update summary where nothing failed stay on the
/// device. An escaped (`uncaught.*`) one is a bug, so it goes up.
///
/// Pure Dart, so `tools/agent/uploadable.dart` judges a device log by the
/// very rule the app ships.
bool isUploadedEntry(DiagnosticEntry e) =>
    e.kind == 'perf.slow' ||
    !e.kind.startsWith('perf.') &&
        !deviceOnlyKinds.contains(e.kind) &&
        !(e.kind == autoUpdateKind && !e.error.contains(autoUpdateFailed)) &&
        (e.kind.startsWith('uncaught.') || !isEnvironmentError(e.error));
