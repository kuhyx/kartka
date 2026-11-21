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
    ContentTypes types,
    int page, {
    String query = '',
  }) async {
    asked.add('${listing.name}/${types.toJson().join('+')}/$page/$query');
    return (page: SearchPage.empty, applied: true);
  }
}

const _manga = ContentTypes({ContentType.manga});

void main() {
  test('ticking toggles one type; all three is all, none is none', () {
    expect(ContentTypes.all.isAll, isTrue);
    final two = ContentTypes.all.toggled(ContentType.manhua);
    expect(two.isAll, isFalse);
    expect(two.contains(ContentType.manhua), isFalse);
    expect(two.toggled(ContentType.manhua), ContentTypes.all);
    expect(_manga.toggled(ContentType.manga).isNone, isTrue);
    expect(two.hashCode, ContentTypes.all.toggled(ContentType.manhua).hashCode);
    expect(two == two.toggled(ContentType.manga), isFalse);
  });

  test('stored as a list in a fixed order; old names still read', () {
    final two = ContentTypes.all.toggled(ContentType.manhua);
    expect(two.toJson(), ['manga', 'manhwa']);
    expect(ContentTypes.parse('["manhwa","manga"]'), two);
    expect(ContentTypes.parse('[]'), ContentTypes.none);
    expect(ContentTypes.parse('["manga","webtoon",1]'), _manga);
    expect(ContentTypes.parse('manga'), _manga);
    expect(ContentTypes.parse('mangaManhwa'), two);
    expect(ContentTypes.parse('all'), ContentTypes.all);
    expect(ContentTypes.parse('webtoon'), isNull);
    expect(ContentTypes.parse('{"a": 1}'), isNull);
    expect(ContentTypes.parse(null), isNull);
  });

  test('all asks the plain listing and counts as applied', () async {
    final s = FakeSource('plain');
    for (final l in Listing.values) {
      final r = await listContent(s, l, ContentTypes.all, 2, query: 'q');
      expect(r.applied, isTrue);
    }
    expect(s.calls, ['popular:2', 'latest:2', 'search(q):2']);
  });

  test('none lists nothing and asks no source', () async {
    final s = _Typed();
    final r = await listContent(s, Listing.popular, ContentTypes.none, 1);
    expect(r.page.items, isEmpty);
    expect(r.page.hasNext, isFalse);
    expect(r.applied, isTrue);
    expect(s.asked, isEmpty);
    expect(s.calls, isEmpty);
  });

  test('a source without a type filter lists unfiltered, not applied', () {
    final s = FakeSource('plain');
    return expectLater(
      listContent(s, Listing.popular, _manga, 1),
      completion(isA<TypedPage>().having((r) => r.applied, 'applied', isFalse)),
    ).then((_) => expect(s.calls, ['popular:1']));
  });

  test('a filterable source is asked for the narrowed listing', () async {
    final s = _Typed();
    final r = await listContent(
      s,
      Listing.search,
      ContentTypes.all.toggled(ContentType.manga),
      3,
      query: 'gate',
    );
    expect(r.applied, isTrue);
    expect(s.asked, ['search/manhwa+manhua/3/gate']);
    expect(s.calls, isEmpty);
    // `all` never reaches the source's narrowed path.
    await listContent(s, Listing.latest, ContentTypes.all, 1);
    expect(s.asked, hasLength(1));
    expect(s.calls, ['latest:1']);
  });

  test('plainListing maps each listing onto MangaSource', () async {
    final MangaSource s = FakeSource('plain');
    await plainListing(s, Listing.latest, 4, '');
    expect((s as FakeSource).calls, ['latest:4']);
  });
}
