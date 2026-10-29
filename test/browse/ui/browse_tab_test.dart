import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/browse/state/shared_health_lookup.dart';
import 'package:kartka/browse/ui/browse_tab.dart';
import 'package:kartka/core/models/models.dart';

import '../fakes.dart';
import 'harness.dart';

void main() {
  final sources = [
    FakeSource('mangadex', name: 'MangaDex'),
    FakeSource('suwayomi:1', name: 'Alpha', origin: SourceOrigin.suwayomi),
    FakeSource('suwayomi:2', name: 'Beta', origin: SourceOrigin.suwayomi),
    FakeSource('local', name: 'Local files', origin: SourceOrigin.local),
  ];

  testWidgets('groups by origin, orders by rank, shows badges', (t) async {
    final h = Harness(
      sources: sources,
      health: const FakeHealth({
        'suwayomi:2': SourceHealthSummary(rank: 1, verdict: HealthVerdict.keep),
        'suwayomi:1': SourceHealthSummary(rank: 5, verdict: HealthVerdict.cut),
      }),
    );
    await h.pump(t, const BrowseTab());
    for (final label in ['Built-in', 'Suwayomi', 'Local']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Plugins'), findsNothing);
    final beta = t.getTopLeft(find.text('Beta')).dy;
    final alpha = t.getTopLeft(find.text('Alpha')).dy;
    expect(beta, lessThan(alpha));
    expect(find.text('badge:keep'), findsOneWidget);
    expect(find.text('badge:cut'), findsOneWidget);
    expect(find.text('EN · #1'), findsOneWidget);
  });

  testWidgets('without health: name order and no badges', (t) async {
    final h = Harness(sources: sources);
    await h.pump(t, const BrowseTab());
    expect(find.textContaining('badge:'), findsNothing);
    expect(
      t.getTopLeft(find.text('Alpha')).dy,
      lessThan(t.getTopLeft(find.text('Beta')).dy),
    );
  });

  testWidgets('sources appearing at runtime show up live', (t) async {
    final h = Harness(sources: []);
    await h.pump(t, const BrowseTab());
    expect(find.text('No sources'), findsOneWidget);
    h.provider.controller.add([
      FakeSource('plugin:x', name: 'Xplug', origin: SourceOrigin.plugin),
    ]);
    await t.pumpAndSettle();
    expect(find.text('Xplug'), findsOneWidget);
    expect(find.text('Plugins'), findsOneWidget);
  });

  testWidgets('tapping a source opens its screen', (t) async {
    final h = Harness(sources: sources);
    await h.pump(t, const BrowseTab());
    await t.tap(find.text('MangaDex'));
    await t.pumpAndSettle();
    expect(find.text('Popular'), findsOneWidget);
    expect(find.text('Title 0'), findsOneWidget);
  });

  testWidgets('global search submits to the search screen', (t) async {
    final h = Harness(sources: sources);
    await h.pump(t, const BrowseTab());
    await t.enterText(find.byType(TextField), '   ');
    await t.testTextInput.receiveAction(TextInputAction.search);
    await t.pumpAndSettle();
    expect(find.text('Built-in'), findsOneWidget); // Blank: stays.
    await t.enterText(find.byType(TextField), 'berserk');
    await t.testTextInput.receiveAction(TextInputAction.search);
    await t.pumpAndSettle();
    expect(find.text('MangaDex'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
    expect(sources.first.calls, contains('search(berserk):1'));
  });

  testWidgets('a rebuild does not resubscribe to source health', (t) async {
    final health = _CountingHealth();
    final h = Harness(sources: sources, health: health);
    await h.pump(t, const BrowseTab());
    h.provider.controller.add([
      FakeSource('plugin:x', name: 'Xplug', origin: SourceOrigin.plugin),
    ]);
    await t.pumpAndSettle();
    expect(find.text('Xplug'), findsOneWidget);
    expect(health.watches, 1);
  });

  testWidgets('a remount starts from the shared lookup latest ranks', (
    t,
  ) async {
    // Only the first subscription ever emits: a remount must not wait.
    final upstream = _CountingHealth(
      data: const {
        'suwayomi:2': SourceHealthSummary(rank: 1, verdict: HealthVerdict.keep),
      },
      emitOnce: true,
    );
    final shared = SharedHealthLookup(upstream);
    final h = Harness(sources: sources, health: shared);
    await h.pump(t, const BrowseTab());
    await t.pumpWidget(const SizedBox());
    await h.pump(t, const BrowseTab(), settle: false);
    expect(find.text('EN · #1'), findsOneWidget);
    expect(upstream.watches, 1);
    // Let the shared subscription's linger timer run out.
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(minutes: 2));
  });
}

class _CountingHealth extends FakeHealth {
  new({Map<String, SourceHealthSummary> data = const {}, this.emitOnce = false})
    : super(data);

  final bool emitOnce;
  int watches = 0;

  @override
  Stream<Map<String, SourceHealthSummary>> watch() {
    watches++;
    return emitOnce && watches > 1 ? const Stream.empty() : super.watch();
  }
}
