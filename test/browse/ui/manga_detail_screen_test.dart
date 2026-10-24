import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/app/routes.dart';
import 'package:kartka/core/models/models.dart';

import '../fakes.dart';
import 'harness.dart';

const _url = '/manga/a b?c=1#d';
final MangaKey _key = mangaKeyOf('mangadex', _url);

Future<Harness> _open(WidgetTester t, {bool downloads = true}) async {
  t.view.physicalSize = const Size(1200, 2400);
  addTearDown(t.view.resetPhysicalSize);
  final h = Harness(withDownloads: downloads);
  await h.pump(t, const SizedBox(), at: mangaRoute('mangadex', _url));
  return h;
}

void main() {
  testWidgets('shows cover, metadata, description, slot, chapters', (t) async {
    await _open(t);
    expect(find.text('Detail title'), findsOneWidget);
    expect(find.text('Author A · ongoing'), findsOneWidget);
    expect(find.text('A long description.'), findsOneWidget);
    expect(find.text('Action'), findsOneWidget);
    expect(find.text('slot:$_key'), findsOneWidget);
    expect(find.text('3 chapters'), findsOneWidget);
    // Newest first in the list.
    expect(
      t.getTopLeft(find.text('Ch. 3')).dy,
      lessThan(t.getTopLeft(find.text('Ch. 1')).dy),
    );
    expect(find.byType(Image), findsWidgets);
  });

  testWidgets('add to and remove from the library', (t) async {
    final h = await _open(t);
    await t.tap(find.byKey(const ValueKey('library')));
    await t.pumpAndSettle();
    expect(h.library.entries[_key]?.title, 'Detail title');
    expect(find.text('In library'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('library')));
    await t.pumpAndSettle();
    expect(h.library.entries, isEmpty);
  });

  testWidgets('mark read / unread per chapter', (t) async {
    final h = await _open(t);
    await t.tap(find.byTooltip('Mark read').last); // Ch. 1
    await t.pumpAndSettle();
    expect(h.progress.marks[_key], {'/c/1': true});
    expect(find.byTooltip('Mark unread'), findsOneWidget);
    await t.tap(find.byTooltip('Mark unread'));
    await t.pumpAndSettle();
    expect(h.progress.marks[_key], {'/c/1': false});
  });

  testWidgets('download one, all and unread', (t) async {
    final h = await _open(t);
    await t.tap(find.byTooltip('Download').first); // Ch. 3
    await h.progress.markRead(_key, '/c/1');
    await t.pumpAndSettle();
    expect(h.downloads.enqueued, ['/c/3']);
    await t.tap(find.byKey(const ValueKey('download-menu')));
    await t.pumpAndSettle();
    await t.tap(find.text('Download unread'));
    await t.pumpAndSettle();
    expect(h.downloads.enqueued, ['/c/3', '/c/2', '/c/3']);
    await t.tap(find.byKey(const ValueKey('download-menu')));
    await t.pumpAndSettle();
    await t.tap(find.text('Download all'));
    await t.pumpAndSettle();
    expect(h.downloads.enqueued, hasLength(6));
    // Pressing the anchor again closes an open menu.
    await t.tap(find.byKey(const ValueKey('download-menu')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('download-menu')));
    await t.pumpAndSettle();
    expect(find.text('Download all'), findsNothing);
  });

  testWidgets('no downloads part: no download buttons', (t) async {
    await _open(t, downloads: false);
    expect(find.byTooltip('Download'), findsNothing);
    expect(find.byKey(const ValueKey('download-menu')), findsNothing);
  });

  testWidgets('Read opens the first unread chapter', (t) async {
    final h = await _open(t);
    await h.progress.markRead(_key, '/c/1');
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('continue')), findsNothing);
    await t.tap(find.byKey(const ValueKey('read')));
    await t.pumpAndSettle();
    expect(find.text('reader:/c/2'), findsOneWidget);
  });

  testWidgets('Continue opens the progress chapter', (t) async {
    final h = await _open(t);
    await h.progress.record(
      ReadingProgress(
        key: _key,
        chapterUrl: '/c/2',
        chapterNumber: 2,
        page: 4,
        readAt: DateTime.utc(2026),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('continue')));
    await t.pumpAndSettle();
    expect(find.text('reader:/c/2'), findsOneWidget);
  });

  testWidgets('tapping a chapter opens the reader', (t) async {
    await _open(t);
    await t.tap(find.text('Ch. 3'));
    await t.pumpAndSettle();
    expect(find.text('reader:/c/3'), findsOneWidget);
  });

  testWidgets('a failing load offers Retry; Refresh reloads', (t) async {
    final src = FakeSource('mangadex')..failWith = StateError('down');
    final h = Harness(sources: [src], withCovers: false);
    await h.pump(t, const SizedBox(), at: mangaRoute('mangadex', _url));
    expect(find.textContaining('Could not load'), findsOneWidget);
    src.failWith = null;
    await t.tap(find.text('Retry'));
    await t.pumpAndSettle();
    expect(find.text('Detail title'), findsOneWidget);
    await t.tap(find.byTooltip('Refresh'));
    await t.pumpAndSettle();
    expect(src.calls.where((c) => c.startsWith('details')), hasLength(3));
  });

  testWidgets('a source id with no MangaSource shows unavailable', (t) async {
    final h = Harness();
    await h.pump(t, const SizedBox(), at: mangaRoute('sy-builtin:42', _url));
    expect(find.text('Source unavailable'), findsOneWidget);
    expect(find.textContaining('sy-builtin:42'), findsOneWidget);
    expect(find.textContaining('Could not load'), findsNothing);
    // It can appear later (e.g. a plugin installed): Retry picks it up.
    h.provider.controller.add([FakeSource('sy-builtin:42')]);
    await t.tap(find.text('Retry'));
    await t.pumpAndSettle();
    expect(find.text('Detail title'), findsOneWidget);
  });
}
