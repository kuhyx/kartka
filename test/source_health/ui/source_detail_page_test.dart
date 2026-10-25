import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/source_health/model/source_health_record.dart';
import 'package:kartka/source_health/ui/source_detail_page.dart';

import '../fixtures.dart';
import 'harness.dart';

Future<void> pumpDetail(
  WidgetTester tester,
  SourceHealthRecord record, {
  DateTime? now,
}) async {
  tallSurface(tester);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildDarkTheme(),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => SourceDetailPage(
                record: record,
                all: fixtureRecords(),
                now: now ?? DateTime.utc(2026, 10, 25),
              ),
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('explains every metric with its threshold and status', (
    tester,
  ) async {
    await pumpDetail(tester, fixtureRecord('plugin:comick'));
    for (final title in [
      'Uptime',
      'Latency',
      'Blocking',
      'Coverage',
      'Chapter completeness',
      'Image quality',
      'Subset of another source',
      'Available as',
    ]) {
      expect(find.text(title), findsWidgets, reason: title);
    }
    expect(find.textContaining('Low-score reason below 95 %'), findsOne);
    expect(find.textContaining('Low-score reason below 60 %'), findsOne);
    expect(find.text('Lowers score'), findsNWidgets(3));
    expect(find.text('Why the score is low'), findsOne);
    expect(find.textContaining('cut', findRichText: true), findsNothing);
    expect(find.textContaining('Blocks automated reading'), findsOne);
    expect(find.text('Score breakdown'), findsOne);
    expect(find.text('Evaluator score 0.41 · rank #5'), findsOne);
    expect(find.text('Last evaluated 2026-10-24 12:00 UTC'), findsOne);
    expect(find.textContaining('older than 8 days'), findsNothing);
  });

  testWidgets('pending source shows accruing state and stale warning', (
    tester,
  ) async {
    await pumpDetail(
      tester,
      fixtureRecord('suwayomi:7034581279101437511'),
      now: DateTime.utc(2026, 12),
    );
    expect(find.text('accruing 9/28 probes'), findsOne);
    expect(find.text('Accruing'), findsOne);
    expect(find.text('Not measured'), findsWidgets);
    expect(find.text('Why the score is low'), findsNothing);
    expect(find.textContaining('older than 8 days'), findsOne);
    expect(find.text('Evaluator score — · unranked'), findsOne);
  });

  testWidgets('subset link opens the covering source', (tester) async {
    await pumpDetail(tester, fixtureRecord('suwayomi:2499283573021220255'));
    await tester.tap(find.text('Open MangaDex'));
    await tester.pumpAndSettle();
    final pages = tester.widgetList<SourceDetailPage>(
      find.byType(SourceDetailPage, skipOffstage: false),
    );
    expect(pages.last.record.id, 'mangadex');
  });

  testWidgets('Escape goes back', (tester) async {
    await pumpDetail(tester, fixtureRecord('local'));
    expect(find.byType(SourceDetailPage), findsOne);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(SourceDetailPage), findsNothing);
  });
}
