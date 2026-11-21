import 'package:design_system/design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kartka/app/app.dart';
import 'package:kartka/app/registry.dart';
import 'package:kartka/browse/state/refresh_outcome.dart';
import 'package:kartka/browse/state/source_wait.dart';
import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:kartka/core/source/unknown_source_error.dart';
import 'package:kartka/core/ui/snack_mark.dart';
import 'package:kartka/core/ui/spoken_label.dart';
import 'package:kartka/source_health/ui/health_icons.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/fake_platform.dart';

void main() {
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
    // Word-free snackbars: the glyph's spoken label is the message.
    await show(
      (c) => ScaffoldMessenger.of(c).showSnackBar(
        const SnackBar(
          content: Icon(Icons.error, semanticLabel: 'Sync failed: 401'),
        ),
      ),
    );
    await show(
      (c) => ScaffoldMessenger.of(c).showSnackBar(
        const SnackBar(
          content: SpokenLabel(
            semanticLabel: 'Download failed: timeout',
            child: Icon(Icons.error),
          ),
        ),
      ),
    );
    // IconValue through showMark (the failing /sources case)
    await show(
      (c) => showMark(
        c,
        const IconValue(
          Icons.error_outline,
          'HTTP 502',
          semanticLabel: 'Install failed',
        ),
        error: true,
      ),
    );
    // A missing source is a known state, not an error to report.
    for (final missing in [
      UnknownSourceError('suwayomi:1'),
      const SourceUnavailable('sy-builtin:6901'),
    ]) {
      await show(
        (c) => ScaffoldMessenger.of(c).showSnackBar(
          SnackBar(
            content: SpokenLabel(
              semanticLabel: refreshMessage(RefreshFailed(missing)),
              child: const Icon(Icons.error_outline),
            ),
          ),
        ),
      );
    }
    final entries = await tester.runAsync(
      () => DiagnosticsLog.of(platform.diagnostics).entries(),
    );
    expect(entries!.map((e) => e.error), [
      'FormatException: repo URL must be http(s): x',
      'Install failed: HTTP 500',
      'Sync failed: 401',
      'Download failed: timeout',
      'Install failed: HTTP 502',
    ]);
    expect(entries.every((e) => e.kind == 'ui.snackbar'), isTrue);
    expect(entries.first.route, '/probe/:id');
    await tester.pumpAndSettle(const Duration(seconds: 10));
  });
}
