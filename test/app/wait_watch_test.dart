import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kartka/app/app.dart';
import 'package:kartka/app/registry.dart';
import 'package:kartka/app/wait_watch.dart';
import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:kartka/platform/platform.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/fake_platform.dart';

Widget _host(KartkaPlatform platform, {required bool showing}) => KartkaScope(
  registry: KartkaRegistry.build(platform, const []),
  platform: platform,
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: showing
        ? const WaitWatch(
            operation: 'library.load',
            child: SizedBox(key: Key('spinner')),
          )
        : const SizedBox(),
  ),
);

void main() {
  late DateTime now;

  /// A platform and log made in the test's own zone (futures born in the
  /// setUp zone would not run on the test clock), reading [now].
  (KartkaPlatform, DiagnosticsLog) setup() {
    final platform = fakePlatform();
    final log = DiagnosticsLog.of(platform.diagnostics)..route = '/library';
    now = DateTime.utc(2026, 11, 17, 12);
    SlowWaitReporter.of(log, now: () => now);
    return (platform, log);
  }

  testWidgets('900 ms on screen reports nothing', (tester) async {
    final (platform, log) = setup();
    await tester.pumpWidget(_host(platform, showing: true));
    expect(find.byKey(const Key('spinner')), findsOneWidget);
    now = now.add(const Duration(milliseconds: 900));
    await tester.pumpWidget(_host(platform, showing: false));
    expect(await tester.runAsync(log.entries), isEmpty);
  });

  testWidgets('1100 ms on screen reports route, operation, duration', (
    tester,
  ) async {
    final (platform, log) = setup();
    await tester.pumpWidget(_host(platform, showing: true));
    now = now.add(const Duration(milliseconds: 1100));
    await tester.pumpWidget(_host(platform, showing: false));
    final e = (await tester.runAsync(log.entries))!.single;
    expect(
      (e.kind, e.route, e.operation, e.durationMs),
      ('perf.slow', '/library', 'library.load', 1100),
    );
  });

  testWidgets('outside a KartkaScope it only shows its child', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: WaitWatch(
          operation: 'x',
          child: SizedBox(key: Key('c')),
        ),
      ),
    );
    expect(find.byKey(const Key('c')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('time in the background does not count as waiting', (
    tester,
  ) async {
    final (platform, log) = setup();
    await tester.pumpWidget(_host(platform, showing: true));
    now = now.add(const Duration(milliseconds: 600));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = now.add(const Duration(minutes: 5));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    now = now.add(const Duration(milliseconds: 600));
    await tester.pumpWidget(_host(platform, showing: false));
    expect(await tester.runAsync(log.entries), isEmpty, reason: '2 x 600 ms');
  });

  testWidgets('a wait on a pushed page is filed under that page', (
    tester,
  ) async {
    final platform = fakePlatform();
    final log = DiagnosticsLog.of(platform.diagnostics);
    now = DateTime.utc(2026, 11, 17, 12);
    SlowWaitReporter.of(log, now: () => now);
    final registry = KartkaRegistry.build(platform, [
      (_) => KartkaFeature(
        id: 'probe',
        routes: [
          GoRoute(
            path: '/probe/:id',
            builder: (_, _) => const WaitWatch.centered('probe.load'),
          ),
        ],
        tabs: {
          KartkaTab.library: (context) => IconButton(
            onPressed: () => context.push('/probe/7'),
            icon: const Icon(Icons.open_in_new),
          ),
        },
      ),
    ]);
    await tester.pumpWidget(KartkaApp(registry: registry, platform: platform));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.open_in_new));
    await tester.pump();
    now = now.add(const Duration(seconds: 2));
    await tester.pumpWidget(const SizedBox());
    final e = (await tester.runAsync(log.entries))!.single;
    expect((e.operation, e.route), ('probe.load', '/probe/:id'));
  });
}
