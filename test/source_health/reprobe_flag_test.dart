// A source the previous run hard-cut gets one reachability request; when it
// fails, the evaluator publishes only that (kuhy, 2026-10-25). The record
// says so with the additive `reprobe-only` flag (plus a `reprobe` block the
// app ignores), and the app shows a "Re-probed only" chip.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/source_health_lookup.dart';
import 'package:kartka/source_health/model/source_health_record.dart';
import 'package:kartka/source_health/scoring/judge.dart';
import 'package:kartka/source_health/scoring/profile.dart';
import 'package:kartka/source_health/ui/health_badge.dart';
import 'package:kartka/source_health/ui/source_card.dart';
import 'package:kartka/source_health/ui/source_detail_page.dart';

import 'fixtures.dart';
import 'ui/harness.dart';

/// Exactly what the evaluator publishes for a failed re-probe.
const reprobedJson = <String, Object?>{
  'id': 'suwayomi:dead',
  'name': 'Dead Site',
  'lang': 'en',
  'origin': 'suwayomi',
  'probedAt': '2026-11-01T10:00:00Z',
  'uptime': {
    'windowDays': 7,
    'probes': 0,
    'ok': 0,
    'ratio': null,
    'status': 'accruing',
  },
  'latencyMs': {'p50': null, 'p95': null},
  'blocking': {'challengeRate': 0.0, 'kinds': <String>[], 'hardRate': 0.0},
  'unreachable': true,
  'flags': ['reprobe-only'],
  'coverage': {
    'referenceSize': 200,
    'found': null,
    'ratio': null,
    'complete': null,
    'completeRatio': null,
  },
  'chapterCompleteness': {'sampled': 0, 'medianRatio': null},
  'imageQuality': {
    'sampledPages': 0,
    'medianWidthPx': null,
    'medianJpegQuality': null,
  },
  'pagesLoad': {'ratio': null, 'sampled': 0},
  'langScope': 'en+ja',
  'availability': {'native': false, 'mangayomiJs': false, 'keiyoushi': true},
  'pkg': 'eu.kanade.tachiyomi.extension.en.dead',
  'plugin': null,
  'reprobe': {'passed': false, 'kind': null, 'previousRun': '2026-W44'},
  'cutReasons': ['unreachable'],
  'subsetOf': null,
  'score': 0.0,
  'defaultScore': 0.0,
  'rank': 9,
  'verdict': 'cut',
};

final Finder chip = find.byType(ReprobeChip);

void main() {
  group('model', () {
    test('the flag parses, is exposed and round-trips', () {
      final r = SourceHealthRecord.fromJson(reprobedJson)!;
      expect(r.flags, [reprobeOnlyFlag]);
      expect(r.reprobedOnly, isTrue);
      expect(r.needsBrowserEngine, isFalse);
      expect(SourceHealthRecord.fromJson(r.toJson()), r);
    });

    test('it stays cut under any profile (hard-filter code)', () {
      final r = SourceHealthRecord.fromJson(reprobedJson)!;
      final everything = defaultScoringProfile.copyWith(keepScore: 0);
      for (final profile in [defaultScoringProfile, everything]) {
        expect(rescore([r], profile).single.verdict, HealthVerdict.cut);
      }
    });

    test('a measured record is not re-probed only', () {
      expect(fixtureRecord('mangadex').reprobedOnly, isFalse);
    });
  });

  group('ui', () {
    testWidgets('the Sources row shows the chip', (tester) async {
      tallSurface(tester);
      final r = SourceHealthRecord.fromJson(reprobedJson)!;
      await tester.pumpWidget(
        host(
          ListView(
            children: [
              SourceCard(record: r, onOpen: (_) {}, nameOf: (_) => null),
              SourceCard(
                record: fixtureRecord('mangadex'),
                onOpen: (_) {},
                nameOf: (_) => null,
              ),
            ],
          ),
        ),
      );
      expect(chip, findsOne);
    });

    testWidgets('the chip has a spoken label', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(const ReprobeChip()));
      expect(
        find.bySemanticsLabel('Only re-probed this run: still unreachable'),
        findsOne,
      );
      handle.dispose();
    });

    testWidgets('the detail page shows the chip', (tester) async {
      tallSurface(tester);
      final r = SourceHealthRecord.fromJson(reprobedJson)!;
      await tester.pumpWidget(
        host(
          SourceDetailPage(record: r, all: [r], now: DateTime.utc(2026, 11, 2)),
        ),
      );
      expect(chip, findsOne);
    });
  });
}
