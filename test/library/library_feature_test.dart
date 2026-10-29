import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kartka/app/feature.dart';
import 'package:kartka/core/repositories/repositories.dart';
import 'package:kartka/library/library_feature.dart';
import 'package:kartka/library/library_repositories.dart';
import 'package:kartka/library/library_routes.dart';
import 'package:kartka/library/repository_decorator.dart';
import 'package:kartka/library/ui/categories_screen.dart';
import 'package:kartka/library/ui/library_screen.dart';
import 'package:kartka/platform/cover_cache.dart';
import 'package:kartka/platform/http_client.dart';
import 'package:kartka/platform/memory/memory_platform.dart';

import 'support/fakes.dart';

class _Counting implements RepositoryDecorator {
  int calls = 0;
  @override
  LibraryRepository library(LibraryRepository inner) {
    calls++;
    return inner;
  }

  @override
  CategoryRepository categories(CategoryRepository inner) => inner;
  @override
  ProgressRepository progress(ProgressRepository inner) => inner;
}

void main() {
  late _Counting decorator;
  late FakeKartkaHttp http;
  late KartkaRegistry registry;
  final unread = FakeUnread();

  setUp(() {
    decorator = _Counting();
    http = FakeKartkaHttp(
      (_) => KartkaResponse(statusCode: 200, bodyBytes: Uint8List(0)),
    );
    registry = KartkaRegistry.build(memoryPlatform(http: http), [
      libraryFeature,
      (_) => KartkaFeature(id: 'other', services: [decorator, unread]),
    ]);
  });

  test('registers one decorated LibraryRepositories', () {
    final repos = registry.maybe<LibraryRepositories>()!;
    expect(repos.library, same(repos.library));
    expect(decorator.calls, 1);
  });

  testWidgets('fills the Library tab and the categories route', (tester) async {
    final tab = registry.tab(KartkaTab.library)!;
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (context, _) => tab(context)),
        ...registry.routes,
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.byType(LibraryScreen), findsOneWidget);
    final screen = tester.widget<LibraryScreen>(find.byType(LibraryScreen));
    expect(screen.deps.unread, same(unread));
    expect(screen.deps.repos, same(registry.maybe<LibraryRepositories>()));
    await tester.runAsync(() => screen.deps.coverLoader!('https://x/c.jpg'));
    expect(http.requests.single.url.toString(), 'https://x/c.jpg');
    // Cached and shared: a second mount costs no request.
    await tester.runAsync(() => screen.deps.coverLoader!('https://x/c.jpg'));
    expect(http.requests, hasLength(1));
    expect(registry.maybe<CoverCache>()!.peek('https://x/c.jpg'), isNotNull);
    router.go(libraryCategoriesRoute);
    await tester.pumpAndSettle();
    final cats = tester.widget<CategoriesScreen>(find.byType(CategoriesScreen));
    expect(cats.deps, same(screen.deps));
  });
}
