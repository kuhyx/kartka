import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/browse/state/shared_health_lookup.dart';
import 'package:kartka/browse/ui/browse_tab.dart';
import 'package:kartka/browse/ui/source_tile.dart';
import 'package:kartka/core/models/models.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/spoken_icon.dart';
import '../fakes.dart';
import 'harness.dart';

void main() {
  final sources = [
    FakeSource('mangadex', name: 'MangaDex'),
    FakeSource('suwayomi:1', name: 'Alpha', origin: SourceOrigin.suwayomi),
    FakeSource('suwayomi:2', name: 'Beta', origin: SourceOrigin.suwayomi),
    FakeSource('local', name: 'Local files', origin: SourceOrigin.local),
  ];

  double x(WidgetTester t, String text) => t.getTopLeft(find.text(text)).dx;

  testWidgets('one grid of every source in rank order, origin as a glyph', (
    t,
  ) async {
    final h = Harness(
      sources: sources,
      health: const FakeHealth({
        'suwayomi:2': SourceHealthSummary(rank: 1, verdict: HealthVerdict.keep),
        'suwayomi:1': SourceHealthSummary(rank: 5, verdict: HealthVerdict.cut),
      }),
    );
    await h.pump(t, const BrowseTab());
    for (final name in ['MangaDex', 'Alpha', 'Beta', 'Local files']) {
      expect(find.text(name), findsOneWidget);
    }
    // Ranked first (Beta #1, Alpha #5), then unranked by name.
    expect(x(t, 'Beta'), lessThan(x(t, 'Alpha')));
    expect(x(t, 'Alpha'), lessThan(x(t, 'Local files')));
    expect(find.text('badge:keep'), findsOneWidget);
    expect(find.text('badge:cut'), findsOneWidget);
    expect(spokenIcon('Suwayomi'), findsNWidgets(2));
    expect(spokenIcon('Built-in'), findsOneWidget);
    expect(spokenIcon('Local'), findsOneWidget);
    expect(find.text('Built-in'), findsNothing); // Never painted.
  });

  testWidgets('long-press shows language, rank and badge', (t) async {
    final h = Harness(
      sources: sources,
      health: const FakeHealth({
        'suwayomi:2': SourceHealthSummary(rank: 1, verdict: HealthVerdict.keep),
      }),
    );
    await h.pump(t, const BrowseTab());
    await t.longPress(find.text('Beta'));
    await t.pumpAndSettle();
    final sheet = find.byType(SourceSheet);
    expect(
      find.descendant(of: sheet, matching: find.text('EN · #1')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('badge:keep')),
      findsOneWidget,
    );
  });

  testWidgets('a rank without a badge is shown on the tile', (t) async {
    final h = Harness(
      sources: [FakeSource('a', name: ' ')],
      health: const _RankOnly(),
    );
    await h.pump(t, const BrowseTab());
    expect(find.text('#3'), findsOneWidget);
    expect(find.text('?'), findsOneWidget);
  });

  testWidgets('the engine warning is an icon on the tile, a chip in the '
      'sheet', (t) async {
    // The stacked rank + "Needs browser engine" badge, squeezed into a
    // 3-column tile, scaled down until it was unreadable on the phone.
    final h = Harness(
      sources: sources,
      health: const FakeHealth({
        'suwayomi:1': SourceHealthSummary(
          rank: 7,
          verdict: HealthVerdict.cut,
          needsBrowserEngine: true,
        ),
      }),
    );
    await h.pump(t, const BrowseTab());
    expect(find.text('badge:cut'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is Icon && w.semanticLabel == 'Needs browser engine',
      ),
      findsOneWidget,
    );
    await t.longPress(find.text('Alpha'));
    await t.pumpAndSettle();
    final sheet = find.byType(SourceSheet);
    expect(
      find.descendant(of: sheet, matching: find.text('badge:cut+engine')),
      findsOneWidget,
    );
  });

  testWidgets('without health: name order and no badges', (t) async {
    final h = Harness(sources: sources);
    await h.pump(t, const BrowseTab());
    expect(find.textContaining('badge:'), findsNothing);
    expect(x(t, 'Alpha'), lessThan(x(t, 'Beta')));
    await t.longPress(find.text('Alpha'));
    await t.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(SourceSheet), matching: find.text('EN')),
      findsOneWidget,
    );
  });

  testWidgets('sources appearing at runtime show up live', (t) async {
    final h = Harness(sources: []);
    await h.pump(t, const BrowseTab());
    expect(find.bySemanticsLabel('No sources'), findsOneWidget);
    h.provider.controller.add([
      FakeSource('plugin:x', name: 'Xplug', origin: SourceOrigin.plugin),
    ]);
    await t.pumpAndSettle();
    expect(find.text('Xplug'), findsOneWidget);
    expect(spokenIcon('Plugins'), findsOneWidget);
  });

  testWidgets('tapping a source opens its screen', (t) async {
    final h = Harness(sources: sources);
    await h.pump(t, const BrowseTab());
    await t.tap(find.text('MangaDex'));
    await t.pumpAndSettle();
    expect(spokenIcon('Popular'), findsOneWidget);
    expect(find.text('Title 0'), findsOneWidget);
  });

  testWidgets('global search submits to the search screen', (t) async {
    final h = Harness(sources: sources);
    await h.pump(t, const BrowseTab());
    await t.enterText(find.byType(TextField), '   ');
    await t.testTextInput.receiveAction(TextInputAction.search);
    await t.pumpAndSettle();
    expect(find.text('Beta'), findsOneWidget); // Blank: stays.
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
    expect(find.text('badge:keep'), findsOneWidget);
    expect(upstream.watches, 1);
    // Let the shared subscription's linger timer run out.
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(minutes: 2));
  });
}

/// Health with a rank but no badge widget.
class _RankOnly extends FakeHealth {
  const new() : super(const {});

  @override
  Stream<Map<String, SourceHealthSummary>> watch() => Stream.value(const {
    'a': SourceHealthSummary(rank: 3, verdict: HealthVerdict.keep),
  });

  @override
  Widget? buildBadge(BuildContext c, String id, SourceHealthSummary? s) => null;
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
