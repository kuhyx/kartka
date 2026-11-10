import 'dart:typed_data';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kartka/app/routes.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/library/library_repositories.dart';
import 'package:kartka/library/ports.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/updates/data/update_feed.dart';
import 'package:kartka/updates/state/updates_deps.dart';
import 'package:kartka/updates/ui/updates_screen.dart';

import '../../helpers/fake_updater.dart';
import '../../helpers/spoken_icon.dart';

ChapterInfo _ch(int n) =>
    ChapterInfo(url: '/c/$n', name: 'Ch. $n', number: n.toDouble());

final _a = LibraryEntry(
  key: mangaKeyOf('mangadex', '/a'),
  sourceId: 'mangadex',
  mangaUrl: '/a',
  title: 'Akira',
  coverUrl: 'https://x.test/a.jpg',
  addedAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

class _H {
  new({required this.withUpdater});
  final bool withUpdater;
  final kv = MemoryKeyValueStore();
  late final repos = LibraryRepositories(kv, decorators: () => []);
  late final feed = UpdateFeed(kv, inLibrary: (_) async => true);
  final updater = FakeUpdater();
  final covers = <String>[];
  late final deps = UpdatesDeps(
    feed: feed,
    library: repos.library,
    progress: repos.progress,
    updater: withUpdater ? updater : null,
    coverLoader: (url) async {
      covers.add(url);
      return Uint8List.fromList([1, 2, 3]);
    },
  );
}

Future<_H> _pump(
  WidgetTester t, {
  bool seed = true,
  bool withUpdater = true,
}) async {
  final h = _H(withUpdater: withUpdater);
  if (seed) {
    await h.repos.library.upsert(_a);
    await h.feed.record(_a.key, [_ch(3), _ch(4)]);
    await h.repos.progress.markRead(_a.key, '/c/3');
  }
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => UpdatesScreen(deps: h.deps),
      ),
      GoRoute(
        path: readRoutePattern,
        builder: (_, s) {
          final r = parseReadRoute(s.uri.toString())!;
          return Text('reader ${r.sourceId} ${r.mangaUrl} ${r.chapterUrl}');
        },
      ),
      GoRoute(
        path: mangaRoutePattern,
        builder: (_, s) {
          final r = parseMangaRoute(s.uri.toString())!;
          return Text('detail ${r.sourceId} ${r.mangaUrl}');
        },
      ),
    ],
  );
  await t.pumpWidget(
    MaterialApp.router(theme: buildDarkTheme(), routerConfig: router),
  );
  await t.pumpAndSettle();
  return h;
}

void main() {
  testWidgets('feed grouped by day and manga, unread dot', (t) async {
    final h = await _pump(t);
    expect(spokenIcon('Today'), findsOneWidget);
    expect(find.text('Akira'), findsOneWidget);
    expect(find.text('Ch. 4'), findsOneWidget);
    expect(find.text('Ch. 3'), findsOneWidget);
    expect(find.byKey(const ValueKey('unread /c/4')), findsOneWidget);
    expect(find.byKey(const ValueKey('unread /c/3')), findsNothing);
    expect(h.covers, ['https://x.test/a.jpg']);
  });

  testWidgets('tapping a chapter opens the reader on it', (t) async {
    await _pump(t);
    await t.tap(find.text('Ch. 4'));
    await t.pumpAndSettle();
    expect(find.text('reader mangadex /a /c/4'), findsOneWidget);
  });

  testWidgets('tapping the manga header opens its detail page', (t) async {
    await _pump(t);
    await t.tap(find.text('Akira'));
    await t.pumpAndSettle();
    expect(find.text('detail mangadex /a'), findsOneWidget);
  });

  testWidgets('new feed entries appear live', (t) async {
    final h = await _pump(t);
    await h.feed.record(_a.key, [_ch(5)]);
    await t.pumpAndSettle();
    expect(find.text('Ch. 5'), findsOneWidget);
  });

  testWidgets('empty state; refresh icon and pull run update-all', (t) async {
    final h = await _pump(t, seed: false);
    expect(spokenIcon('No updates yet'), findsOneWidget);
    h.updater.summary = const UpdateSummary(newChapters: 2, manga: 1);
    await t.tap(spokenIcon('Check for updates'));
    await t.pumpAndSettle();
    expect(h.updater.calls, 1);
    expect(find.bySemanticsLabel('2 new chapters in 1 manga'), findsOne);
    await t.fling(spokenIcon('No updates yet'), const Offset(0, 400), 1000);
    await t.pumpAndSettle();
    expect(h.updater.calls, 2);
  });

  testWidgets('progress of a run shows under the bar', (t) async {
    final h = await _pump(t);
    h.updater.show(const UpdateProgress(12, 87));
    await t.pump();
    expect(find.text('12/87'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    h.updater.show(null);
    await t.pump();
    expect(find.text('12/87'), findsNothing);
  });

  testWidgets('a manga removed from the library drops out of the feed', (
    t,
  ) async {
    final h = await _pump(t);
    await h.repos.library.remove(_a.key);
    await t.pumpAndSettle();
    expect(find.text('Akira'), findsNothing);
    expect(spokenIcon('No updates yet'), findsOneWidget);
  });

  testWidgets('no updater: no refresh action, no pull', (t) async {
    await _pump(t, withUpdater: false);
    expect(find.text('Ch. 4'), findsOneWidget);
    expect(spokenIcon('Check for updates'), findsNothing);
    expect(find.byType(RefreshIndicator), findsNothing);
  });
}
