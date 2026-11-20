import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/browse_routes.dart';
import 'package:kartka/browse/state/browse_content_type_store.dart';
import 'package:kartka/core/source/content_type.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/spoken_icon.dart';
import '../fakes.dart';
import 'harness.dart';

const _manga = 'Manga only';
const _both = 'Manga and manhwa';
const _all = 'All types';
const _notApplied = 'Type filter not applied here';

/// Narrows Popular and Search; Latest it cannot narrow (no sort option).
class _Typed extends FakeSource implements ContentTypeFilterable {
  new(super.id, {super.name}) : super(pageCount: 1);

  @override
  Future<TypedPage> listTyped(
    Listing listing,
    ContentType type,
    int page, {
    String query = '',
  }) async {
    final p = listing == Listing.search
        ? await search(query, page)
        : await plainListing(this, listing, page, query);
    calls.add('${listing.name}/${type.name}');
    return (page: p, applied: listing != Listing.latest);
  }
}

void main() {
  testWidgets('the toggle cycles the setting and refetches', (t) async {
    final kv = MemoryKeyValueStore();
    final src = _Typed('mf');
    final h = Harness(sources: [src], contentType: BrowseContentTypeStore(kv));
    await h.pump(t, const SizedBox(), at: sourceRoute('mf'));
    expect(src.calls, ['popular:1', 'popular/manga']);
    expect(spokenIcon(_notApplied), findsNothing);

    await t.tap(spokenIcon(_manga));
    await t.pumpAndSettle();
    expect(spokenIcon(_both), findsOneWidget);
    expect(src.calls.last, 'popular/mangaManhwa');
    expect(await kv.get(BrowseContentTypeStore.storageKey), 'mangaManhwa');

    src.calls.clear();
    await t.tap(spokenIcon(_both));
    await t.pumpAndSettle();
    expect(spokenIcon(_all), findsOneWidget);
    // `all` is today's request exactly.
    expect(src.calls, ['popular:1']);

    await t.tap(spokenIcon(_all));
    await t.pumpAndSettle();
    expect(spokenIcon(_manga), findsOneWidget);
    expect(src.calls.last, 'popular/manga');
  });

  testWidgets('the mark follows the tab that could not narrow', (t) async {
    final src = _Typed('mf');
    final h = Harness(sources: [src]);
    await h.pump(t, const SizedBox(), at: sourceRoute('mf'));
    await t.tap(spokenIcon('Latest'));
    await t.pumpAndSettle();
    expect(src.calls, contains('latest/manga'));
    expect(spokenIcon(_notApplied), findsOneWidget);
    await t.tap(spokenIcon('Popular'));
    await t.pumpAndSettle();
    expect(spokenIcon(_notApplied), findsNothing);
  });

  testWidgets('a source without a type filter shows the mark, not on all', (
    t,
  ) async {
    final src = FakeSource('plain', pageCount: 1);
    final store = BrowseContentTypeStore(null);
    final h = Harness(sources: [src], contentType: store);
    await h.pump(t, const SizedBox(), at: sourceRoute('plain'));
    expect(src.calls, ['popular:1']);
    expect(spokenIcon(_notApplied), findsOneWidget);
    await store.cycle();
    await store.cycle();
    await t.pumpAndSettle();
    expect(spokenIcon(_notApplied), findsNothing);
  });

  testWidgets('global search re-runs with the new type; marks per row', (
    t,
  ) async {
    final typed = _Typed('mf', name: 'MangaFire');
    final plain = FakeSource('p', name: 'Plain', pageCount: 1);
    final h = Harness(sources: [typed, plain]);
    await h.pump(t, const SizedBox(), at: globalSearchRoute('gate'));
    expect(typed.calls, ['search(gate):1', 'search/manga']);
    // Only the plain source's row carries the mark.
    expect(spokenIcon(_notApplied), findsOneWidget);
    final plainRow = find.ancestor(
      of: spokenIcon(_notApplied),
      matching: find.byType(ListTile),
    );
    expect(
      find.descendant(of: plainRow, matching: find.text('Plain')),
      findsOneWidget,
    );

    await t.tap(spokenIcon(_manga));
    await t.pumpAndSettle();
    expect(typed.calls.last, 'search/mangaManhwa');
    expect(plain.calls, ['search(gate):1', 'search(gate):1']);
    expect(find.text('MangaFire'), findsOneWidget);
  });
}
