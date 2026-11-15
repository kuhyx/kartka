import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/state/browse_language_store.dart';
import 'package:kartka/browse/state/browse_shown_store.dart';
import 'package:kartka/browse/ui/browse_tab.dart';
import 'package:kartka/browse/ui/language_mark.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/platform/memory/memory_stores.dart';

import '../../helpers/spoken_icon.dart';
import '../fakes.dart';
import 'harness.dart';

void main() {
  List<FakeSource> mixed() => [
    FakeSource('plugin:pl', name: 'Polski', lang: 'pl'),
    FakeSource('suwayomi:ja', name: 'Raw JP', lang: 'ja'),
    FakeSource(
      'suwayomi:multi',
      name: 'Multi',
      lang: 'multi',
      origin: SourceOrigin.suwayomi,
    ),
    FakeSource('all', name: 'Everything', lang: 'all'),
    FakeSource('mangadex', name: 'MangaDex'),
  ];

  // The chips in order: '*' for All, else the bucket.
  List<String> chips(WidgetTester t) => [
    for (final c in t.widgetList<ChoiceChip>(find.byType(ChoiceChip)))
      switch (c.label) {
        final LanguageMark m => m.bucket,
        _ => '*',
      },
  ];

  Future<void> tapChip(WidgetTester t, String key) async {
    await t.tap(find.byKey(ValueKey(key)));
    await t.pumpAndSettle();
  }

  Future<void> openPicker(WidgetTester t) async {
    await t.tap(spokenIcon('Languages'));
    await t.pumpAndSettle();
  }

  testWidgets('unset: All, then en, all/multi, ja chips; each its own grid', (
    t,
  ) async {
    final h = Harness(sources: mixed());
    await h.pump(t, const BrowseTab());
    expect(chips(t), ['*', 'en', 'all', 'ja']);
    expect(find.text('Polski'), findsNothing);
    for (final n in ['MangaDex', 'Everything', 'Multi', 'Raw JP']) {
      expect(find.text(n), findsOneWidget);
    }
    await tapChip(t, 'lang-chip-all');
    expect(find.text('MangaDex'), findsNothing);
    expect(find.text('Everything'), findsOneWidget);
    expect(find.text('Multi'), findsOneWidget);
    await tapChip(t, 'lang-chip-ja');
    expect(find.text('Raw JP'), findsOneWidget);
    expect(find.text('Multi'), findsNothing);
    await tapChip(t, 'lang-chip-*');
    expect(find.text('MangaDex'), findsOneWidget);
  });

  testWidgets('the chip choice is remembered across remounts and restarts', (
    t,
  ) async {
    final kv = MemoryKeyValueStore();
    final h = Harness(sources: mixed(), shown: BrowseShownStore(kv));
    await h.pump(t, const BrowseTab());
    await tapChip(t, 'lang-chip-ja');
    expect(await kv.get(BrowseShownStore.storageKey), 'ja');
    await t.pumpWidget(const SizedBox());
    await h.pump(t, const BrowseTab());
    expect(find.text('MangaDex'), findsNothing);
    expect(find.text('Raw JP'), findsOneWidget);

    final fresh = BrowseShownStore(kv);
    await fresh.ready;
    expect(fresh.value, 'ja');
    await fresh.set(null);
    expect(await kv.get(BrowseShownStore.storageKey), isNull);
  });

  testWidgets('a remembered language without sources falls back to All', (
    t,
  ) async {
    final kv = MemoryKeyValueStore({BrowseShownStore.storageKey: 'ko'});
    final shown = BrowseShownStore(kv);
    await shown.ready;
    final h = Harness(sources: mixed(), shown: shown);
    await h.pump(t, const BrowseTab());
    expect(find.text('MangaDex'), findsOneWidget);
    final all = t.widget<ChoiceChip>(find.byKey(const ValueKey('lang-chip-*')));
    expect(all.selected, isTrue);
  });

  testWidgets('an in-memory choice is kept without a store', (t) async {
    final shown = BrowseShownStore(null);
    await shown.set('ja');
    expect(shown.value, 'ja');
  });

  testWidgets('the picker lists present languages with counts, selected '
      'first; toggling shows and hides sources and persists', (t) async {
    final kv = MemoryKeyValueStore();
    final h = Harness(sources: mixed(), languages: BrowseLanguageStore(kv));
    await h.pump(t, const BrowseTab());
    await openPicker(t);
    final dialog = find.byType(AlertDialog);
    final tiles = find.descendant(
      of: dialog,
      matching: find.byType(CheckboxListTile),
    );
    expect(tiles, findsNWidgets(4));
    String title(int i) =>
        ((t.widget<CheckboxListTile>(tiles.at(i)).title!) as LanguageMark)
            .bucket;
    expect([for (var i = 0; i < 4; i++) title(i)], ['en', 'all', 'ja', 'pl']);
    Finder count(String painted, String spoken) => find.descendant(
      of: dialog,
      matching: find.byWidgetPredicate(
        (w) => w is Text && w.data == painted && w.semanticsLabel == spoken,
      ),
    );
    expect(count('2', '2 sources'), findsOneWidget);
    expect(count('1', '1 source'), findsNWidgets(3));

    await t.tap(find.descendant(of: dialog, matching: find.text('PL')));
    await t.tap(find.descendant(of: dialog, matching: find.text('EN')));
    await t.pumpAndSettle();
    expect(title(0), 'all');
    await t.tap(spokenIcon('Done'));
    await t.pumpAndSettle();
    expect(find.text('Polski'), findsOneWidget);
    expect(chips(t), ['*', 'all', 'ja', 'pl']);
    await tapChip(t, 'lang-chip-pl');
    expect(find.text('Polski'), findsOneWidget);
    expect(find.text('MangaDex'), findsNothing);
    expect(jsonDecode((await kv.get(BrowseLanguageStore.storageKey))!), [
      'all',
      'ja',
      'pl',
    ]);

    final fresh = BrowseLanguageStore(kv);
    await fresh.ready;
    expect(fresh.value, ['all', 'ja', 'pl']);
  });

  testWidgets('a filter that hides every source says so', (t) async {
    final kv = MemoryKeyValueStore({
      BrowseLanguageStore.storageKey: jsonEncode(['ko']),
    });
    final store = BrowseLanguageStore(kv);
    await store.ready;
    final h = Harness(sources: mixed(), languages: store);
    await h.pump(t, const BrowseTab());
    expect(spokenIcon('No sources in your languages'), findsOneWidget);
    expect(spokenIcon('No sources'), findsNothing);
  });

  testWidgets('the + chip opens the picker too', (t) async {
    final h = Harness(sources: mixed());
    await h.pump(t, const BrowseTab());
    await t.tap(find.byKey(const ValueKey('lang-add')));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('the picker with no sources installed says so', (t) async {
    final h = Harness(sources: []);
    await h.pump(t, const BrowseTab());
    await openPicker(t);
    expect(spokenIcon('No sources installed yet'), findsOneWidget);
    await t.tap(spokenIcon('Done'));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
}
