import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kartka/app/routes.dart';
import 'package:kartka/library/library_routes.dart';
import 'package:kartka/library/state/library_deps.dart';
import 'package:kartka/library/ui/categories_screen.dart';
import 'package:kartka/library/ui/library_screen.dart';

/// Pumps the Library screen at `/` inside a router that also knows the
/// detail route (rendered as decoded text) and the categories screen.
Future<GoRouter> pumpLibrary(WidgetTester tester, LibraryDeps deps) async {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => LibraryScreen(deps: deps),
      ),
      GoRoute(
        path: mangaRoutePattern,
        builder: (_, state) {
          final r = parseMangaRoute(state.uri.toString())!;
          return Text('detail ${r.sourceId} ${r.mangaUrl}');
        },
      ),
      GoRoute(
        path: libraryCategoriesRoute,
        builder: (_, _) => CategoriesScreen(deps: deps),
      ),
    ],
  );
  await tester.pumpWidget(
    MaterialApp.router(theme: buildDarkTheme(), routerConfig: router),
  );
  await tester.pumpAndSettle();
  return router;
}
