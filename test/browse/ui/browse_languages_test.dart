import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/state/browse_language_store.dart';
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

  // A source name is painted; a language heading only speaks its name.
  double y(WidgetTester t, String text) {
    final painted = find.text(text);
    final f = painted.evaluate().isEmpty ? spokenContaining(text) : painted;
    return t.getTopLeft(f).dy;
  }

  // Tall enough that every section is built (ListView builds lazily).
  void tall(WidgetTester t) {
    t.view
      ..physicalSize = const Size(800, 2400)
      ..devicePixelRatio = 1;
    addTearDown(t.view.reset);
  }

  Future<void> openPicker(WidgetTester t) async {
    await t.tap(spokenIcon('Languages'));
    await t.pumpAndSettle();
  }

  testWidgets('unset: only en, all/multi, ja are shown, in that order', (
    t,
  ) async {
    tall(t);
    final h = Harness(sources: mixed());
    await h.pump(t, const BrowseTab());
    expect(find.text('Polski'), findsNothing);
    expect(y(t, 'English'), lessThan(y(t, 'MangaDex')));
    expect(y(t, 'MangaDex'), lessThan(y(t, 'All languages')));
    expect(y(t, 'All languages'), lessThan(y(t, 'Everything')));
    expect(y(t, 'Everything'), lessThan(y(t, 'Multi')));
    expect(y(t, 'Multi'), lessThan(y(t, 'Japanese')));
    expect(y(t, 'Japanese'), lessThan(y(t, 'Raw JP')));
  });

  testWidgets('the picker lists present languages with counts, selected '
      'first; toggling shows and hides sources and persists', (t) async {
    tall(t);
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

    expect(
      find.descendant(of: dialog, matching: spokenIcon('All languages')),
      findsOne,
    );
    await t.tap(find.descendant(of: dialog, matching: find.text('PL')));
    await t.tap(find.descendant(of: dialog, matching: find.text('EN')));
    await t.pumpAndSettle();
    expect(title(0), 'all');
    await t.tap(spokenIcon('Done'));
    await t.pumpAndSettle();
    expect(find.text('Polski'), findsOneWidget);
    expect(find.text('MangaDex'), findsNothing);
    expect(y(t, 'Raw JP'), lessThan(y(t, 'Polski')));
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
