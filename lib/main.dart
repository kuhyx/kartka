// coverage:ignore-file
// Entry point: builds the real platform and registry, then hands over to
// KartkaApp (covered by test/app/shell_test.dart).
import 'package:flutter/widgets.dart';
import 'package:kartka/app/app.dart';
import 'package:kartka/app/error_hooks.dart';
import 'package:kartka/app/redacted_logging.dart';
import 'package:kartka/app/registry.dart';
import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:kartka/platform/create_platform.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  installRedactedLogging();
  final platform = await createPlatform();
  installErrorReporting(
    ErrorReporter.of(DiagnosticsLog.of(platform.diagnostics)),
  );
  final registry = KartkaRegistry.build(platform, kartkaFeatureFactories);
  runApp(KartkaApp(registry: registry, platform: platform));
}
