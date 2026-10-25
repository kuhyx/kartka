import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/source_health/model/source_health_record.dart';
import 'package:kartka/source_health/ui/source_card.dart';
import 'package:kartka/source_health/ui/source_detail_page.dart';

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

void main() {
  testWidgets('card: pages load tile and language scope when present', (
    tester,
  ) async {
    await pumpCard(tester, _keptWithReasons);
    expect(find.text('Pages load'), findsOne);
    expect(find.text('92 % of 25 sampled'), findsOne);
    expect(find.text('Suwayomi · en · tested EN + JA only'), findsOne);
    await pumpCard(tester, _cut);
    expect(find.text('— of 4 sampled'), findsOne);
  });

  testWidgets('card: no pages-load tile on older records', (tester) async {
    await pumpCard(
      tester,
      SourceHealthRecord.fromJson(const {'id': 'o', 'verdict': 'keep'})!,
    );
    expect(find.text('Pages load'), findsNothing);
  });

  testWidgets('card: a kept source shows its reasons as warnings', (
    tester,
  ) async {
    await pumpCard(tester, _keptWithReasons);
    expect(find.text('Kept on score ≥ 0.90 despite:'), findsOne);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOne);
    expect(find.textContaining('Catalogue too small'), findsOne);
    await pumpCard(tester, _cut);
    expect(find.textContaining('despite'), findsNothing);
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
    expect(find.textContaining('Catalogue too small'), findsOne);
  });

  testWidgets('detail: warnings section and pages-load metric for a keep', (
    tester,
  ) async {
    await pumpDetail(tester, _keptWithReasons);
    expect(find.text('Why it was cut'), findsNothing);
    expect(find.text('Kept on score ≥ 0.90 despite'), findsOne);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOne);
    expect(find.text('Pages load'), findsOne);
    expect(find.text('92 % of 25 sampled'), findsOne);
    expect(find.textContaining('tested EN + JA only'), findsOne);
  });

  testWidgets('detail: a cut source still explains why', (tester) async {
    await pumpDetail(tester, _cut);
    expect(find.text('Why it was cut'), findsOne);
    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
  });
}
