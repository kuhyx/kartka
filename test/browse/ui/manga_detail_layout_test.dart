import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/app/routes.dart';
import 'package:kartka/browse/state/chapter_sort_store.dart';
import 'package:kartka/core/models/models.dart';

import '../../helpers/spoken_icon.dart';
import '../fakes.dart';
import 'harness.dart';

const _url = '/m/1';
final MangaKey _key = mangaKeyOf('mangadex', _url);

/// A source whose details are as noisy as a real one: 20 tags, long text.
class _RichSource extends FakeSource {
  new() : super('mangadex', chapters: _upTo(30));

  @override
  Future<MangaDetails> details(String mangaUrl) async => MangaDetails(
    sourceId: ref.id,
    url: mangaUrl,
    title: 'Detail title',
    authors: const ['Author A'],
    description: 'Long. ' * 120,
    genres: [for (var i = 0; i < 20; i++) 'Genre number $i'],
    status: MangaStatus.ongoing,
  );
}

List<ChapterInfo> _upTo(int last) => [
  for (var n = last; n >= 1; n--)
    ChapterInfo(url: '/c/$n', name: 'Ch. $n', number: n.toDouble()),
];

Future<Harness> _open(WidgetTester t, {FakeSource? source}) async {
  t.view
    ..devicePixelRatio = 1
    ..physicalSize = const Size(400, 800);
  addTearDown(t.view.reset);
  final h = Harness(sources: [source ?? FakeSource('mangadex')]);
  await h.pump(t, const SizedBox(), at: mangaRoute('mangadex', _url));
  return h;
}

List<String> _order(WidgetTester t, List<String> names) => [...names]
  ..sort(
    (a, b) =>
        t.getTopLeft(find.text(a)).dy.compareTo(t.getTopLeft(find.text(b)).dy),
  );

void main() {
  testWidgets('header is collapsed: tap shows tags and description', (t) async {
    await _open(t);
    expect(find.text('Detail title'), findsOneWidget);
    expect(find.text('Author A'), findsOneWidget);
    expect(spokenIcon('ongoing'), findsOneWidget);
    expect(find.text('A long description.'), findsNothing);
    expect(find.text('Action'), findsNothing);
    await t.tap(find.byKey(const ValueKey('detail-header')));
    await t.pumpAndSettle();
    expect(find.text('A long description.'), findsOneWidget);
    expect(find.text('Action'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('detail-header')));
    await t.pumpAndSettle();
    expect(find.text('A long description.'), findsNothing);
  });

  testWidgets('chapters are on screen without scrolling at 800 px', (t) async {
    await _open(t, source: _RichSource());
    for (final n in [30, 29, 28, 27, 26, 25]) {
      final tile = find.text('Ch. $n');
      expect(tile.hitTestable(), findsOneWidget, reason: 'Ch. $n');
      expect(t.getBottomLeft(tile).dy, lessThan(800), reason: 'Ch. $n');
    }
  });

  testWidgets('the Continue FAB is always there', (t) async {
    final h = await _open(t);
    final fab = find.byKey(const ValueKey('continue'));
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(
      find.descendant(of: fab, matching: spokenIcon('Continue')),
      findsOne,
    );
    await t.tap(fab); // No progress: the first unread chapter.
    await t.pumpAndSettle();
    expect(find.text('reader:/c/1'), findsOneWidget);
    await h.progress.record(
      ReadingProgress(
        key: _key,
        chapterUrl: '/c/2',
        chapterNumber: 2,
        page: 3,
        readAt: DateTime.utc(2026),
      ),
    );
    await h.pump(t, const SizedBox(), at: mangaRoute('mangadex', _url));
    await t.tap(find.byKey(const ValueKey('continue')));
    await t.pumpAndSettle();
    expect(find.text('reader:/c/2'), findsOneWidget);
  });

  testWidgets('no chapters: no FAB', (t) async {
    await _open(t, source: FakeSource('mangadex', chapters: const []));
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('the overflow menu holds every other action', (t) async {
    await _open(t);
    expect(spokenIcon('Add to library'), findsNothing);
    await t.tap(spokenIcon('More'));
    await t.pumpAndSettle();
    for (final label in [
      'Read',
      'Add to library',
      'Download all',
      'Download unread',
      'Unread first',
    ]) {
      expect(spokenIcon(label), findsOneWidget, reason: label);
    }
    expect(find.text('slot:$_key'), findsOneWidget);
    await t.tap(spokenIcon('More')); // Toggles closed.
    await t.pumpAndSettle();
    expect(spokenIcon('Add to library'), findsNothing);
    // A slot is no menu item, yet tapping it closes the menu too.
    await t.tap(spokenIcon('More'));
    await t.pumpAndSettle();
    await t.tap(find.text('slot:$_key'));
    await t.pumpAndSettle();
    expect(spokenIcon('Add to library'), findsNothing);
  });

  testWidgets('unread: full brightness + accent dot; read: dimmed', (t) async {
    final h = await _open(t);
    await h.progress.markRead(_key, '/c/1');
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('unread-dot-/c/3')), findsOneWidget);
    expect(find.byKey(const ValueKey('unread-dot-/c/1')), findsNothing);
    final dot = t.widget<DecoratedBox>(
      find.descendant(
        of: find.byKey(const ValueKey('unread-dot-/c/3')),
        matching: find.byType(DecoratedBox),
      ),
    );
    expect((dot.decoration as BoxDecoration).color, AppPalette.accent);
    final scheme = Theme.of(t.element(find.text('Ch. 1'))).colorScheme;
    Color? colorOf(String text) => t.widget<Text>(find.text(text)).style?.color;
    expect(colorOf('Ch. 1'), scheme.onSurfaceVariant);
    expect(colorOf('Ch. 3'), scheme.onSurface);
  });

  testWidgets('"Unread first" reorders and is remembered', (t) async {
    final h = await _open(t);
    await h.progress.markRead(_key, '/c/3');
    await t.pumpAndSettle();
    expect(_order(t, ['Ch. 1', 'Ch. 2', 'Ch. 3']), ['Ch. 3', 'Ch. 2', 'Ch. 1']);
    await t.tap(spokenIcon('More'));
    await t.pumpAndSettle();
    await t.tap(spokenIcon('Unread first'));
    await t.pumpAndSettle();
    expect(_order(t, ['Ch. 1', 'Ch. 2', 'Ch. 3']), ['Ch. 2', 'Ch. 1', 'Ch. 3']);
    expect(await h.sortKv.get(ChapterSortStore.storageKey), 'true');
    // Another manga page opens sorted the same way: the setting is global.
    await h.pump(t, const SizedBox(), at: mangaRoute('mangadex', '/m/2'));
    expect(_order(t, ['Ch. 1', 'Ch. 2', 'Ch. 3']), ['Ch. 3', 'Ch. 2', 'Ch. 1']);
    await h.progress.markRead(mangaKeyOf('mangadex', '/m/2'), '/c/3');
    await t.pumpAndSettle();
    expect(_order(t, ['Ch. 1', 'Ch. 2', 'Ch. 3']), ['Ch. 2', 'Ch. 1', 'Ch. 3']);
    await t.tap(spokenIcon('More'));
    await t.pumpAndSettle();
    await t.tap(spokenIcon('Unread first'));
    await t.pumpAndSettle();
    expect(await h.sortKv.get(ChapterSortStore.storageKey), 'false');
  });
}
