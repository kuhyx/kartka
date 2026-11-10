import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/source_health/model/source_health_record.dart';
import 'package:kartka/source_health/ui/reason_marks.dart';
import 'package:kartka/source_health/ui/source_card.dart';
import 'package:kartka/source_health/ui/source_detail_page.dart';

import '../../helpers/spoken_icon.dart';
import 'harness.dart';

final SourceHealthRecord _keptWithReasons = SourceHealthRecord.fromJson(const {
  'id': 'k',
  'name': 'Keeper',
  'lang': 'en',
  'origin': 'suwayomi',
  'verdict': 'keep',
  'score': 0.93,
  'langScope': 'en+ja',
  'pagesLoad': {'ratio': 0.92, 'sampled': 25},
  'coverage': {'referenceSize': 650, 'found': 300, 'ratio': 0.46},
  'cutReasons': ['coverage<0.60'],
})!;

final SourceHealthRecord _cut = SourceHealthRecord.fromJson(const {
  'id': 'c',
  'name': 'Cutter',
  'verdict': 'cut',
  'pagesLoad': {'sampled': 4},
  'cutReasons': ['coverage<0.60'],
})!;

Future<void> pumpCard(WidgetTester tester, SourceHealthRecord r) =>
    tester.pumpWidget(
      host(SourceCard(record: r, onOpen: (_) {}, nameOf: (_) => null)),
    );

Future<void> pumpDetail(WidgetTester tester, SourceHealthRecord r) async {
  tallSurface(tester);
  await tester.pumpWidget(
    host(
      SourceDetailPage(record: r, all: [r], now: DateTime.utc(2026, 10, 25)),
    ),
  );
}

/// The "kept despite" heading glyph of the reasons.
final Finder _reasonWarning = find.descendant(
  of: find.byType(ReasonMarks),
  matching: find.byIcon(Icons.warning_amber_rounded),
);

void main() {
  testWidgets('card: pages load tile and language scope when present', (
    tester,
  ) async {
    await pumpCard(tester, _keptWithReasons);
    expect(spokenIcon('Pages load: 92 % of 25 sampled'), findsOne);
    expect(find.text('92 % · 25'), findsOne);
    expect(spokenContaining('Suwayomi · en · tested EN + JA only'), findsOne);
    expect(find.text('en · EN+JA'), findsOne);
    await pumpCard(tester, _cut);
    expect(find.text('— · 4'), findsOne);
  });

  testWidgets('card: no pages-load tile on older records', (tester) async {
    await pumpCard(
      tester,
      SourceHealthRecord.fromJson(const {'id': 'o', 'verdict': 'keep'})!,
    );
    expect(spokenContaining('Pages load'), findsNothing);
  });

  testWidgets('card: a kept source shows its reasons as warnings', (
    tester,
  ) async {
    await pumpCard(tester, _keptWithReasons);
    expect(spokenIcon('Kept on score ≥ 0.90 despite'), findsOne);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOne);
    expect(spokenContaining('Catalogue too small'), findsOne);
    await pumpCard(tester, _cut);
    expect(spokenContaining('despite'), findsNothing);
    expect(spokenIcon('Why the score is low'), findsOne);
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
    expect(spokenContaining('Catalogue too small'), findsOne);
  });

  testWidgets('detail: warnings section and pages-load metric for a keep', (
    tester,
  ) async {
    await pumpDetail(tester, _keptWithReasons);
    expect(spokenIcon('Why the score is low'), findsNothing);
    expect(spokenIcon('Kept on score ≥ 0.90 despite'), findsOne);
    expect(pill('Lowers score'), findsNothing);
    expect(pill('Warns'), findsOne);
    expect(find.text('× 0.92'), findsOne);
    expect(find.textContaining('× 92 %'), findsOne);
    expect(_reasonWarning, findsOne);
    expect(spokenContaining('Pages load: '), findsOne);
    expect(find.text('92 % · 25'), findsOne);
    expect(spokenContaining('tested EN + JA only'), findsOne);
  });

  testWidgets('detail: a cut source still explains why', (tester) async {
    await pumpDetail(tester, _cut);
    expect(spokenIcon('Why the score is low'), findsOne);
    expect(spokenIcon('Pages load (multiplier)'), findsOne);
    expect(_reasonWarning, findsNothing);
  });
}
