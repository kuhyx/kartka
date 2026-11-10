import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/app/routes.dart';
import 'package:kartka/core/models/models.dart';

import '../../helpers/spoken_icon.dart';
import '../fakes.dart';
import 'harness.dart';

const _url = '/manga/a b?c=1#d';

List<ChapterInfo> _upTo(int last) => [
  for (var n = last; n >= 1; n--)
    ChapterInfo(url: '/c/$n', name: 'Ch. $n', number: n.toDouble()),
];

Future<(Harness, FakeSource)> _open(WidgetTester t, {int last = 100}) async {
  t.view.physicalSize = const Size(1200, 2400);
  addTearDown(t.view.resetPhysicalSize);
  final src = FakeSource('mangadex', chapters: _upTo(last));
  final h = Harness(sources: [src], withCovers: false);
  await h.pump(t, const SizedBox(), at: mangaRoute('mangadex', _url));
  return (h, src);
}

Future<void> _pull(WidgetTester t) async {
  await t.fling(find.byType(CustomScrollView), const Offset(0, 600), 1000);
  await t.pumpAndSettle();
}

Future<void> _tapRefresh(WidgetTester t) async {
  await t.tap(spokenIcon('Refresh'));
  await t.pumpAndSettle();
}

Finder _said(String label) => find.bySemanticsLabel(label);

void main() {
  testWidgets('the first load shows no snackbar', (t) async {
    await _open(t);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('pull-to-refresh with nothing new', (t) async {
    final (h, src) = await _open(t);
    await _pull(t);
    expect(_said('No new chapters'), findsOneWidget);
    expect(find.byIcon(Icons.done_all), findsOneWidget);
    expect(src.calls.where((c) => c.startsWith('chapters')), hasLength(2));
    expect(await h.diagnostics.entries(), isEmpty);
  });

  testWidgets('pull-to-refresh lists three new chapters', (t) async {
    final (_, src) = await _open(t);
    src.chapterList = _upTo(103);
    await _pull(t);
    expect(_said('3 new: ch 101, 102, 103'), findsOneWidget);
    expect(find.text('3 · 101, 102, 103'), findsOneWidget);
    expect(_said('103 chapters'), findsOneWidget);
    expect(find.text('103'), findsOneWidget);
  });

  testWidgets('seven new chapters list five then +2 more', (t) async {
    final (_, src) = await _open(t);
    src.chapterList = _upTo(107);
    await _pull(t);
    expect(_said('7 new: ch 101, 102, 103, 104, 105 +2 more'), findsOne);
    expect(find.text('7 · 101, 102, 103, 104, 105 +2'), findsOne);
  });

  testWidgets('the app-bar Refresh takes the same path', (t) async {
    final (_, src) = await _open(t);
    await _tapRefresh(t);
    expect(_said('No new chapters'), findsOneWidget);
    src.chapterList = _upTo(103);
    await _tapRefresh(t);
    expect(_said('3 new: ch 101, 102, 103'), findsOneWidget);
  });

  testWidgets('a failed refresh: redacted snackbar + diagnostics', (t) async {
    final (h, src) = await _open(t);
    src.failWith = StateError('down https://h.test/x?auth=SECRET');
    await _pull(t);
    expect(
      _said('Refresh failed: Bad state: down https://h.test/x?<redacted>'),
      findsOneWidget,
    );
    expect(
      find.text('Bad state: down https://h.test/x?<redacted>'),
      findsOneWidget,
    );
    // The old chapters stay on screen.
    expect(_said('100 chapters'), findsOneWidget);
    final entries = await t.runAsync(h.diagnostics.entries);
    expect(entries, hasLength(1));
    final e = entries!.single;
    expect(e.kind, 'details.refresh');
    expect(e.sourceId, 'mangadex');
    expect(e.mangaUrl, isNull);
    final json = jsonEncode(e.toJson());
    expect(json, isNot(contains('SECRET')));
    expect(json, isNot(contains('https://')));
    expect(json, isNot(contains('?c=1')));
  });

  testWidgets('a failed app-bar refresh logs too', (t) async {
    final (h, src) = await _open(t);
    src.failWith = StateError('gone /manga/a?token=X');
    await _tapRefresh(t);
    expect(find.bySemanticsLabel(RegExp('^Refresh failed: ')), findsOne);
    final entries = (await t.runAsync(h.diagnostics.entries))!;
    expect(entries.single.kind, 'details.refresh');
    expect(entries.single.error, isNot(contains('token=X')));
  });

  testWidgets('after a failed first load nothing counts as new', (t) async {
    t.view.physicalSize = const Size(1200, 2400);
    addTearDown(t.view.resetPhysicalSize);
    final src = FakeSource('mangadex', chapters: _upTo(100))
      ..failWith = StateError('down');
    final h = Harness(sources: [src], withCovers: false);
    await h.pump(t, const SizedBox(), at: mangaRoute('mangadex', _url));
    src.failWith = null;
    await _tapRefresh(t);
    expect(_said('100 chapters'), findsOneWidget);
    expect(_said('No new chapters'), findsOneWidget);
  });
}
