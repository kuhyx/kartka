import 'package:glados/glados.dart';
import 'package:kartka/app/routes.dart';

import '../helpers/generators.dart';

void main() {
  test('paths have one encoded segment per argument', () {
    expect(mangaRoute('mangadex', '/title/1'), '/manga/mangadex/%2Ftitle%2F1');
    expect(
      readRoute('suwayomi:1', 'm?x=1', 'c#2'),
      '/read/suwayomi%3A1/m%3Fx%3D1/c%232',
    );
  });

  Glados3(any.text, any.text, any.text).test('parsers invert builders', (
    s,
    m,
    c,
  ) {
    expect(parseMangaRoute(mangaRoute(s, m)), (sourceId: s, mangaUrl: m));
    expect(parseReadRoute(readRoute(s, m, c)), (
      sourceId: s,
      mangaUrl: m,
      chapterUrl: c,
    ));
  });

  test('parsers reject other paths', () {
    expect(parseMangaRoute('/read/a/b/c'), isNull);
    expect(parseMangaRoute('/manga/a'), isNull);
    expect(parseMangaRoute('manga/a/b'), isNull);
    expect(parseMangaRoute('http://h:x/manga/a/b'), isNull);
    // Uri.parse re-escapes a stray %, so a malformed escape survives as text.
    expect(parseMangaRoute('/manga/a/%zz')?.mangaUrl, '%zz');
    expect(parseReadRoute('/manga/a/b'), isNull);
    expect(parseReadRoute('/read/a/b/c/d'), isNull);
  });

  test('go_router patterns name the parameters', () {
    expect(mangaRoutePattern, '/manga/:sourceId/:mangaUrl');
    expect(readRoutePattern, '/read/:sourceId/:mangaUrl/:chapterUrl');
  });
}
