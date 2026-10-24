import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/browse_scope.dart';
import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/browse/state/manga_detail_controller.dart';
import 'package:kartka/browse/ui/chapter_tile.dart';
import 'package:kartka/core/models/models.dart';

import 'ui/harness.dart';

void main() {
  testWidgets('of() throws without a scope', (t) async {
    await t.pumpWidget(Builder(builder: (c) => Text('${BrowseScope.of(c)}')));
    expect(t.takeException(), isA<StateError>());
  });

  test('updateShouldNotify compares deps', () {
    final a = Harness().deps;
    final s = BrowseScope(deps: a, child: const SizedBox());
    expect(s.updateShouldNotify(BrowseScope(deps: a, child: s)), isFalse);
    final other = BrowseScope(deps: Harness().deps, child: s);
    expect(s.updateShouldNotify(other), isTrue);
  });

  test('summary built at runtime', () {
    final rank = DateTime.now().year > 0 ? 2 : 3;
    expect(
      SourceHealthSummary(verdict: HealthVerdict.keep, rank: rank).rank,
      2,
    );
  });

  testWidgets('chapter row shows scanlator and upload date', (t) async {
    final h = Harness();
    await t.pumpWidget(
      BrowseScope(
        deps: h.deps,
        child: MaterialApp(
          home: Material(
            child: ChapterTile(
              controller: MangaDetailController(
                h.deps,
                sourceId: 'mangadex',
                mangaUrl: '/m',
              ),
              chapter: ChapterInfo(
                url: '/c',
                name: 'Ch',
                scanlator: 'Group',
                uploadedAt: DateTime(2026, 3, 4, 12),
              ),
              read: false,
              canDownload: false,
            ),
          ),
        ),
      ),
    );
    expect(find.text('Group · 2026-03-04'), findsOneWidget);
  });
}
