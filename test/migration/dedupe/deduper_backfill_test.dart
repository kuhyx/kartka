import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/migration/dedupe/library_deduper.dart';

import '../../core/updates/backfill_fakes.dart';
import 'dedupe_fakes.dart';

void main() {
  test('a duplicate with no stored list is fetched, then merged', () async {
    final d = DedupeWorld();
    await d.add('good', rank: 1);
    final bad = await d.add('bad', authors: ['Kirihara Idumi'], rank: 9);
    final pending = <MangaKey, DupeFacts>{
      bad.key: d.facts.byKey.remove(bad.key)!,
    };
    final backfill = backfillOf(
      MovingChecker(pending, d.facts.byKey),
      dedupeNow,
    );
    expect(await d.make().run(), 0);
    expect(await d.make(backfill: backfill).run(), 1);
    expect(await d.w.entries(), hasLength(1));
  });
}
