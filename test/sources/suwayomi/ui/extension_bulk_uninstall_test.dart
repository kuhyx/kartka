import 'package:design_system/design_system.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/sources/suwayomi/suwayomi_extensions.dart';
import 'package:kartka/sources/suwayomi/ui/extensions_screen.dart';
import 'package:material_ui/material_ui.dart';

SuwayomiExtension _ext(
  String pkg,
  String name, {
  List<String> ids = const [],
}) => SuwayomiExtension(
  pkgName: pkg,
  name: name,
  lang: 'en',
  versionName: '1',
  iconUrl: '',
  isInstalled: true,
  hasUpdate: false,
  isObsolete: false,
  sourceIds: ids,
);

class _Catalog implements ExtensionCatalog {
  final List<SuwayomiExtension> items = [
    _ext('x.en.mangafire', 'MangaFire', ids: ['suwayomi:1']),
    _ext('x.en.atsumaru', 'Atsumaru', ids: ['suwayomi:2']),
    _ext('x.en.comick', 'Comick', ids: ['suwayomi:3', 'suwayomi:4']),
    _ext('x.en.allanime', 'AllAnime', ids: ['suwayomi:5']),
  ];
  final uninstalled = <String>[];

  @override
  Future<List<SuwayomiExtension>> list() async => items;

  @override
  Future<SuwayomiExtension> uninstall(String pkgName) async {
    uninstalled.add(pkgName);
    final e = items.firstWhere((e) => e.pkgName == pkgName);
    return SuwayomiExtension(
      pkgName: e.pkgName,
      name: e.name,
      lang: e.lang,
      versionName: e.versionName,
      iconUrl: '',
      isInstalled: false,
      hasUpdate: false,
      isObsolete: false,
    );
  }

  @override
  Future<SuwayomiExtension> install(String pkgName) =>
      throw UnimplementedError();

  @override
  Future<SuwayomiExtension> update(String pkgName) =>
      throw UnimplementedError();
}

// Library titles by source id: 2 on Comick's sources, 1 on AllAnime's.
Future<List<String>> _titles() async => [
  'suwayomi:3',
  'suwayomi:4',
  'suwayomi:5',
  'suwayomi:1',
  'mangadex',
];

Future<_Catalog> _pump(WidgetTester tester) async {
  final catalog = _Catalog();
  tester.view.physicalSize = const Size(1080, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildDarkTheme(),
      home: ExtensionsScreen(api: catalog, librarySourceIds: _titles),
    ),
  );
  await tester.pumpAndSettle();
  return catalog;
}

bool _ticked(WidgetTester tester, String name) => tester
    .widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, name))
    .value!;

void main() {
  testWidgets('the uninstall confirm counts the library titles it affects', (
    tester,
  ) async {
    final catalog = await _pump(tester);
    await tester.tap(find.bySemanticsLabel('Uninstall').at(2));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(Badge, '2'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Uninstall').last);
    await tester.pumpAndSettle();
    expect(catalog.uninstalled, ['x.en.comick']);
  });

  testWidgets('no library titles: no badge', (tester) async {
    final catalog = await _pump(tester);
    await tester.tap(find.bySemanticsLabel('Uninstall').at(1));
    await tester.pumpAndSettle();
    expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isFalse);
    await tester.tap(find.bySemanticsLabel('Cancel'));
    await tester.pumpAndSettle();
    expect(catalog.uninstalled, isEmpty);
  });

  testWidgets('bulk uninstall keeps MangaFire and Atsumaru by default', (
    tester,
  ) async {
    final catalog = await _pump(tester);
    await tester.tap(find.bySemanticsLabel('Uninstall all but ticked'));
    await tester.pumpAndSettle();
    expect(_ticked(tester, 'MangaFire'), isTrue);
    expect(_ticked(tester, 'Atsumaru'), isTrue);
    expect(_ticked(tester, 'Comick'), isFalse);
    expect(_ticked(tester, 'AllAnime'), isFalse);
    await tester.tap(find.bySemanticsLabel('Uninstall the unticked'));
    await tester.pumpAndSettle();
    // One confirm for the lot: 3 library titles lose their source.
    expect(find.widgetWithText(Badge, '3'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Uninstall').last);
    await tester.pumpAndSettle();
    expect(catalog.uninstalled, ['x.en.comick', 'x.en.allanime']);
  });

  testWidgets('the keep-list is one-off and a cancel uninstalls nothing', (
    tester,
  ) async {
    final catalog = await _pump(tester);
    await tester.tap(find.bySemanticsLabel('Uninstall all but ticked'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Comick'));
    await tester.tap(find.widgetWithText(CheckboxListTile, 'MangaFire'));
    await tester.pumpAndSettle();
    expect(_ticked(tester, 'Comick'), isTrue);
    await tester.tap(find.bySemanticsLabel('Uninstall the unticked'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Cancel'));
    await tester.pumpAndSettle();
    expect(catalog.uninstalled, isEmpty);
    // Dismissing the sheet also does nothing.
    await tester.tap(find.bySemanticsLabel('Uninstall all but ticked'));
    await tester.pumpAndSettle();
    expect(_ticked(tester, 'MangaFire'), isTrue);
    expect(_ticked(tester, 'Comick'), isFalse);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(catalog.uninstalled, isEmpty);
  });
}
