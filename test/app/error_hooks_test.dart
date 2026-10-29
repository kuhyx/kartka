import 'dart:ui' show ErrorCallback, PlatformDispatcher;

import 'package:design_system/design_system.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kartka/app/app.dart';
import 'package:kartka/app/error_hooks.dart';
import 'package:kartka/app/registry.dart';
import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:kartka/platform/memory/memory_stores.dart';

import '../helpers/fake_platform.dart';

void main() {
  group('installErrorReporting', () {
    late FlutterExceptionHandler? savedFlutter;
    late ErrorCallback? savedAsync;
    late DiagnosticsLog log;
    late List<String> chained;

    setUp(() {
      savedFlutter = FlutterError.onError;
      savedAsync = PlatformDispatcher.instance.onError;
      chained = [];
      FlutterError.onError = (d) => chained.add('flutter ${d.exception}');
      PlatformDispatcher.instance.onError = (e, _) {
        chained.add('async $e');
        return true;
      };
      log = DiagnosticsLog(MemoryBlobStore());
      installErrorReporting(ErrorReporter(log));
    });

    tearDown(() {
      FlutterError.onError = savedFlutter;
      PlatformDispatcher.instance.onError = savedAsync;
    });

    test('framework errors are logged, then the old handler runs', () async {
      FlutterError.onError!(
        FlutterErrorDetails(
          exception: StateError('build broke'),
          stack: StackTrace.fromString('#0 b (package:kartka/x.dart:1)'),
        ),
      );
      FlutterError.onError!(
        FlutterErrorDetails(exception: StateError('quiet'), silent: true),
      );
      final e = (await log.entries()).single;
      expect(e.kind, 'uncaught.flutter');
      expect(e.error, 'Bad state: build broke');
      expect(e.stack.single, contains('package:kartka/x.dart'));
      expect(chained, [
        'flutter Bad state: build broke',
        'flutter Bad state: quiet',
      ]);
    });

    test('async errors are logged and keep the old verdict', () async {
      final handled = PlatformDispatcher.instance.onError!(
        const FormatException('bad'),
        StackTrace.empty,
      );
      expect(handled, isTrue);
      expect(chained, ['async FormatException: bad']);
      final e = (await log.entries()).single;
      expect(e.kind, 'uncaught.async');
      expect(e.error, 'FormatException: bad');
    });

    test('without an old async handler the error stays unhandled', () {
      PlatformDispatcher.instance.onError = null;
      installErrorReporting(ErrorReporter(log));
      expect(
        PlatformDispatcher.instance.onError!(StateError('x'), StackTrace.empty),
        isFalse,
      );
    });
  });

  testWidgets('error snackbars are logged with the route, toasts are not', (
    tester,
  ) async {
    final platform = fakePlatform();
    void Function(BuildContext)? action;
    final registry = KartkaRegistry.build(platform, [
      (_) => KartkaFeature(
        id: 'probe',
        routes: [
          GoRoute(
            path: '/probe/:id',
            builder: (context, _) => TextButton(
              onPressed: () => action!(context),
              child: const Text('act'),
            ),
          ),
        ],
        tabs: {
          KartkaTab.library: (context) => TextButton(
            onPressed: () => context.push('/probe/7'),
            child: const Text('open'),
          ),
        },
      ),
    ]);
    await tester.pumpWidget(KartkaApp(registry: registry, platform: platform));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    Future<void> show(void Function(BuildContext) a) async {
      action = a;
      await tester.tap(find.text('act'));
      await tester.pump();
    }

    await show(
      (c) => showError(c, 'FormatException: repo URL must be http(s): x'),
    );
    await show((c) => showToast(c, 'Removed 2 from library'));
    await show(
      (c) => ScaffoldMessenger.of(
        c,
      ).showSnackBar(const SnackBar(content: Text('Install failed: HTTP 500'))),
    );
    await show(
      (c) =>
          ScaffoldMessenger.of(c)
              .showSnackBar(const SnackBar(content: Icon(Icons.error))),
    );
    await show(
      (c) =>
          ScaffoldMessenger.of(c)
              .showSnackBar(const SnackBar(content: Text('Chapter 12'))),
    );
    final entries = await tester.runAsync(
      () => DiagnosticsLog.of(platform.diagnostics).entries(),
    );
    expect(entries!.map((e) => e.error), [
      'FormatException: repo URL must be http(s): x',
      'Install failed: HTTP 500',
    ]);
    expect(entries.every((e) => e.kind == 'ui.snackbar'), isTrue);
    expect(entries.first.route, '/probe/:id');
    await tester.pumpAndSettle(const Duration(seconds: 10));
  });
}
