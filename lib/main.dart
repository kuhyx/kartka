// coverage:ignore-file
// Entry point: builds the real platform and registry, then hands over to
// KartkaApp (covered by test/app/shell_test.dart).
import 'package:crdt_sync_flutter/crdt_sync_flutter.dart' show installAppErrors;
import 'package:flutter/widgets.dart';
import 'package:kartka/app/app.dart';
import 'package:kartka/app/app_errors.dart';
import 'package:kartka/app/redacted_logging.dart';
import 'package:kartka/app/registry.dart';
import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:kartka/platform/create_platform.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  installRedactedLogging();
  final platform = await createPlatform();
  final log = DiagnosticsLog.of(platform.diagnostics)..stampBuild();
  // Every error and every wait over 1 s goes to the PC's app-errors ingest,
  // which files a board ticket (kuhyx/utils DOCS-app-errors.md); kartka's
  // own reports pass the environment filter on the way (app_errors.dart).
  final errors = await installAppErrors(kartkaErrorsConfig());
  bridgeDiagnostics(log, errors);
  final registry = KartkaRegistry.build(platform, kartkaFeatureFactories);
  runApp(KartkaApp(registry: registry, platform: platform));
}
