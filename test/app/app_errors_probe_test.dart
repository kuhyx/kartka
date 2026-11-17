import 'dart:convert';
import 'dart:io';

import 'package:crdt_sync_flutter/crdt_sync_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/app/app_errors.dart';
import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The done check of the shared reporter: one error and one 2 s wait, each
/// uploaded with the build; kartka's own reports pass the environment
/// filter on the way (offline stays on the device, a bug goes up), and the
/// screen observer stamps the route pattern.
void main() {
  late FlutterExceptionHandler? flutterBefore;
  late bool Function(Object, StackTrace)? asyncBefore;
  setUp(() {
    flutterBefore = FlutterError.onError;
    asyncBefore = PlatformDispatcher.instance.onError;
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() {
    FlutterError.onError = flutterBefore;
    PlatformDispatcher.instance.onError = asyncBefore;
    AppErrors.instance = null;
  });

  testWidgets('an error and a 2 s wait reach the sink with the build', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('kartka_errors');
    addTearDown(() => dir.deleteSync(recursive: true));
    final sinkFile = File('${dir.path}/sink.jsonl');
    final errors = await tester.runAsync(
      () => installAppErrors(kartkaErrorsConfig(build: 557, version: 'probe')),
    );
    final log = DiagnosticsLog(MemoryBlobStore());
    addTearDown(bridgeDiagnostics(log, errors!).cancel);
    ErrorRouteObserver(errors).screenChanged('/library');

    await tester.pumpWidget(
      const MaterialApp(home: WaitWatch.centered('library.load')),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2100)),
    );
    await tester.pumpWidget(const SizedBox());
    FlutterError.reportError(
      FlutterErrorDetails(exception: StateError('probe boom')),
    );
    // Chained on to flutter_test's own handler, which records it.
    expect(tester.takeException(), isA<StateError>());
    await tester.runAsync(() async {
      await log.append(
        DiagnosticEntry(
          at: DateTime.utc(2026, 11, 18),
          kind: 'updates.offline',
          error:
              "ClientException with SocketException: Failed host lookup: 'x'",
        ),
      );
      await log.append(
        DiagnosticEntry(
          at: DateTime.utc(2026, 11, 18),
          kind: 'details.load',
          error: 'SuwayomiException: response has no data',
          route: '/manga/:sourceId/:mangaUrl',
        ),
      );
      final uploader = ErrorUploader(
        errors.queue,
        config: errors.config,
        sink: () async =>
            (String path, Map<String, Object?> values) async =>
                sinkFile.writeAsStringSync(
                  '${jsonEncode({'path': path, 'values': values})}\n',
                  mode: FileMode.append,
                ),
        deviceId: () async => 'probe-device',
      );
      expect(await uploader.flush(), isTrue);
    });

    final sent = [
      for (final line in sinkFile.readAsLinesSync())
        for (final v in ((jsonDecode(line) as Map)['values'] as Map).values)
          v as Map<String, Object?>,
    ];
    final kinds = [for (final e in sent) e['kind']]..sort();
    expect(kinds, ['details.load', 'perf.slow', 'uncaught.flutter']);
    expect(sent.map((e) => e['build']).toSet(), {557});
    final slow = sent.singleWhere((e) => e['kind'] == 'perf.slow');
    expect(slow['route'], '/library');
    expect(slow['operation'], 'library.load');
    expect(slow['durationMs']! as int, greaterThan(1000));
    final bug = sent.singleWhere((e) => e['kind'] == 'details.load');
    expect(bug['route'], '/manga/:sourceId/:mangaUrl');
    final first = jsonDecode(sinkFile.readAsLinesSync().first) as Map;
    expect(first['path'], 'kartka/errors');
  });
}
