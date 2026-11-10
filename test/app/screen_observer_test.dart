import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kartka/app/app.dart';
import 'package:kartka/app/registry.dart';
import 'package:kartka/app/screen_observer.dart';
import 'package:kartka/app/shell.dart';

import '../helpers/fake_platform.dart';

class _Seen implements ScreenObserver {
  final patterns = <String>[];

  @override
  void screenChanged(String pattern) => patterns.add(pattern);
}

void main() {
  testWidgets('reports route patterns, never the concrete location', (
    tester,
  ) async {
    final seen = _Seen();
    final platform = fakePlatform();
    final registry = KartkaRegistry.build(platform, [
      (_) => KartkaFeature(
        id: 'probe',
        services: [seen],
        routes: [
          GoRoute(
            path: '/probe/:id',
            builder: (context, _) => TextButton(
              onPressed: () => context.pop(),
              child: const Text('back'),
            ),
          ),
        ],
        tabs: {
          KartkaTab.library: (context) => TextButton(
            onPressed: () => context.push(
              '/probe/12345?q=${Uri.encodeComponent('https://x.y/a')}',
            ),
            child: const Text('open'),
          ),
        },
      ),
    ]);
    await tester.pumpWidget(KartkaApp(registry: registry, platform: platform));
    await tester.pumpAndSettle();
    expect(seen.patterns, ['/library']);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('back'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(tabInfo[KartkaTab.more]!.icon));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byIcon(tabInfo[KartkaTab.more]!.icon),
    ); // same screen again: no report
    await tester.pumpAndSettle();
    expect(seen.patterns, ['/library', '/probe/:id', '/library', '/more']);

    await tester.pumpWidget(const SizedBox());
    expect(seen.patterns, hasLength(4));
  });
}
