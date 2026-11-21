import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/browse_routes.dart';
import 'package:kartka/browse/state/browse_content_type_store.dart';
import 'package:kartka/core/source/content_type.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/spoken_icon.dart';
import '../fakes.dart';
import 'harness.dart';

const _types = 'Content types';
const _notApplied = 'Type filter not applied here';
const _noneTicked = 'No content type ticked';

/// Narrows Popular and Search; Latest it cannot narrow (no sort option).
class _Typed extends FakeSource implements ContentTypeFilterable {
  new(super.id, {super.name}) : super(pageCount: 1);

  @override
  Future<TypedPage> listTyped(
    Listing listing,
    ContentTypes types,
    int page, {
    String query = '',
  }) async {
    final p = listing == Listing.search
        ? await search(query, page)
        : await plainListing(this, listing, page, query);
    calls.add('${listing.name}/${types.toJson().join('+')}');
    return (page: p, applied: listing != Listing.latest);
  }
}

/// A store holding [ticked] (default: manga only).
Future<BrowseContentTypeStore> _store(
  MemoryKeyValueStore kv, [
  List<String> ticked = const ['manga'],
]) async {
  await kv.set(BrowseContentTypeStore.storageKey, '["${ticked.join('","')}"]');
  final store = BrowseContentTypeStore(kv);
  await store.ready;
  return store;
}

Badge _badge(WidgetTester t) => t.widget<Badge>(
  find.ancestor(of: spokenIcon(_types), matching: find.byType(Badge)),
);

Future<void> _tick(WidgetTester t, String label) async {
  await t.tap(find.widgetWithText(CheckboxListTile, label));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('the sheet ticks types, badges the count and refetches', (
    t,
  ) async {
    final kv = MemoryKeyValueStore();
    final src = _Typed('mf');
    final h = Harness(sources: [src], contentType: BrowseContentTypeStore(kv));
    await h.pump(t, const SizedBox(), at: sourceRoute('mf'));
    // Default: every type ticked, today's plain request.
    expect(src.calls, ['popular:1']);
    expect((_badge(t).label! as Text).data, '3');

    await t.tap(spokenIcon(_types));
    await t.pumpAndSettle();
    for (final label in ['Manga', 'Manhwa', 'Manhua']) {
      final box = find.widgetWithText(CheckboxListTile, label);
      expect(t.widget<CheckboxListTile>(box).value, isTrue, reason: label);
    }
    await _tick(t, 'Manhua');
    expect(src.calls.last, 'popular/manga+manhwa');
    await _tick(t, 'Manhwa');
    expect(src.calls.last, 'popular/manga');
    expect((_badge(t).label! as Text).data, '1');
    expect(await kv.get(BrowseContentTypeStore.storageKey), '["manga"]');

    // None ticked: an empty list with a hint icon; no source is asked.
    src.calls.clear();
    await _tick(t, 'Manga');
    expect(src.calls, isEmpty);
    await t.tapAt(const Offset(10, 10));
    await t.pumpAndSettle();
    expect(spokenIcon(_noneTicked), findsOneWidget);
    expect(_badge(t).isLabelVisible, isFalse);

    await t.tap(spokenIcon(_types));
    await t.pumpAndSettle();
    await _tick(t, 'Manhua');
    expect(src.calls.last, 'popular/manhua');
  });

  testWidgets('the mark follows the tab that could not narrow', (t) async {
    final src = _Typed('mf');
    final h = Harness(
      sources: [src],
      contentType: await _store(MemoryKeyValueStore()),
    );
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
    final store = await _store(MemoryKeyValueStore());
    final h = Harness(sources: [src], contentType: store);
    await h.pump(t, const SizedBox(), at: sourceRoute('plain'));
    expect(src.calls, ['popular:1']);
    expect(spokenIcon(_notApplied), findsOneWidget);
    await store.toggle(ContentType.manhwa);
    await store.toggle(ContentType.manhua);
    await t.pumpAndSettle();
    expect(spokenIcon(_notApplied), findsNothing);
  });

  testWidgets('global search re-runs with the new types; marks per row', (
    t,
  ) async {
    final typed = _Typed('mf', name: 'MangaFire');
    final plain = FakeSource('p', name: 'Plain', pageCount: 1);
    final h = Harness(
      sources: [typed, plain],
      contentType: await _store(MemoryKeyValueStore()),
    );
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

    await t.tap(spokenIcon(_types));
    await t.pumpAndSettle();
    await _tick(t, 'Manhwa');
    expect(typed.calls.last, 'search/manga+manhwa');
    expect(plain.calls, ['search(gate):1', 'search(gate):1']);
  });
}
