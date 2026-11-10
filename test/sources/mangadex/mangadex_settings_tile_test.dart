import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/sources/mangadex/mangadex_settings.dart';
import 'package:kartka/sources/mangadex/mangadex_settings_store.dart';
import 'package:kartka/sources/mangadex/mangadex_settings_tile.dart';

void main() {
  late MangadexSettingsStore store;

  Future<void> pumpTile(WidgetTester tester) async {
    store = MangadexSettingsStore(MemoryKeyValueStore());
    await tester.runAsync(() => store.ready);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MangadexSettingsTile(store: store)),
      ),
    );
  }

  test('summary and language parsing', () {
    expect(settingsSummary(MangadexSettings.defaults), 'en · Safe, Suggestive');
    expect(
      settingsSummary(MangadexSettings.defaults.copyWith(dataSaver: true)),
      'en · Safe, Suggestive',
    );
    expect(parseLanguages(' EN, pt-br  pl,,en '), ['en', 'pt-br', 'pl']);
  });

  testWidgets('tile shows the summary and opens the dialog', (tester) async {
    await pumpTile(tester);
    expect(find.text('en · Safe, Suggestive'), findsOneWidget);
    expect(find.byIcon(Icons.data_saver_on), findsNothing);
    await tester.tap(find.byType(ListTile));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('Chapter languages')), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(store.value, MangadexSettings.defaults);
  });

  testWidgets('editing and saving updates the store and tile', (tester) async {
    await pumpTile(tester);
    await tester.tap(find.byType(ListTile));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('mangadex-languages')),
      'pl, en',
    );
    await tester.tap(find.byType(Switch));
    await tester.tap(find.widgetWithText(FilterChip, 'Erotica'));
    await tester.tap(find.widgetWithText(FilterChip, 'Safe'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Save'));
    await tester.pumpAndSettle();
    expect(store.value.languages, ['pl', 'en']);
    expect(store.value.dataSaver, isTrue);
    expect(store.value.ratings, {
      ContentRating.suggestive,
      ContentRating.erotica,
    });
    expect(find.text('pl, en · Suggestive, Erotica'), findsOne);
    expect(find.byIcon(Icons.data_saver_on), findsOne);
  });

  testWidgets('the last rating cannot be deselected', (tester) async {
    await pumpTile(tester);
    await tester.tap(find.byType(ListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'Safe'));
    await tester.tap(find.widgetWithText(FilterChip, 'Suggestive'));
    await tester.pump();
    final chip = tester.widget<FilterChip>(
      find.widgetWithText(FilterChip, 'Suggestive'),
    );
    expect(chip.selected, isTrue);
  });

  testWidgets('Enter in the language field saves; blank keeps old', (
    tester,
  ) async {
    await pumpTile(tester);
    await tester.tap(find.byType(ListTile));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('mangadex-languages')), ' ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(store.value.languages, ['en']);
  });
}
