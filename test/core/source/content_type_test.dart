import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/source/content_type.dart';
import 'package:kartka/core/source/manga_source.dart';

import '../../browse/fakes.dart';

/// A source that narrows every listing and records what it was asked.
class _Typed extends FakeSource implements ContentTypeFilterable {
  new() : super('typed');

  final asked = <String>[];

  @override
  Future<TypedPage> listTyped(
    Listing listing,
    ContentType type,
    int page, {
    String query = '',
  }) async {
    asked.add('${listing.name}/${type.name}/$page/$query');
    return (page: SearchPage.empty, applied: true);
  }
}

void main() {
  test('the toggle cycles manga, manga+manhwa, all, then manga again', () {
    expect(ContentType.manga.next, ContentType.mangaManhwa);
    expect(ContentType.mangaManhwa.next, ContentType.all);
    expect(ContentType.all.next, ContentType.manga);
  });

  test('stored names parse back; anything else is null', () {
    for (final t in ContentType.values) {
      expect(ContentType.tryParse(t.name), t);
    }
    expect(ContentType.tryParse('manhua'), isNull);
    expect(ContentType.tryParse(null), isNull);
  });

  test('all asks the plain listing and counts as applied', () async {
    final s = FakeSource('plain');
    for (final l in Listing.values) {
      final r = await listContent(s, l, ContentType.all, 2, query: 'q');
      expect(r.applied, isTrue);
    }
    expect(s.calls, ['popular:2', 'latest:2', 'search(q):2']);
  });

  test('a source without a type filter lists unfiltered, not applied', () {
    final s = FakeSource('plain');
    return expectLater(
      listContent(s, Listing.popular, ContentType.manga, 1),
      completion(isA<TypedPage>().having((r) => r.applied, 'applied', isFalse)),
    ).then((_) => expect(s.calls, ['popular:1']));
  });

  test('a filterable source is asked for the narrowed listing', () async {
    final s = _Typed();
    final r = await listContent(
      s,
      Listing.search,
      ContentType.mangaManhwa,
      3,
      query: 'gate',
    );
    expect(r.applied, isTrue);
    expect(s.asked, ['search/mangaManhwa/3/gate']);
    expect(s.calls, isEmpty);
    // `all` never reaches the source's narrowed path.
    await listContent(s, Listing.latest, ContentType.all, 1);
    expect(s.asked, hasLength(1));
    expect(s.calls, ['latest:1']);
  });

  test('plainListing maps each listing onto MangaSource', () async {
    final MangaSource s = FakeSource('plain');
    await plainListing(s, Listing.latest, 4, '');
    expect((s as FakeSource).calls, ['latest:4']);
  });
}
