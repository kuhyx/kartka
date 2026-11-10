import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/downloads/download_service.dart';
import 'package:kartka/downloads/ui/downloads_screen.dart';
import 'package:kartka/downloads/ui/queue_tile.dart';

import '../fakes.dart';
import '../service_harness.dart';

Future<void> _show(
  WidgetTester tester,
  DownloadService s, {
  VoidCallback? onOpen,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildDarkTheme(),
      home: DownloadsScreen(
        service: s,
        titles: Stream.value({mangaKey: 'Berserk'}),
        onOpen: onOpen,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('empty state and zero usage; onOpen fires', (tester) async {
    var opened = 0;
    await _show(tester, Harness().service(), onOpen: () => opened++);
    expect(find.bySemanticsLabel('No downloads'), findsOneWidget);
    expect(find.bySemanticsLabel('Storage used: 0 B'), findsOneWidget);
    expect(find.text('0 B'), findsOneWidget);
    expect(opened, 1);
  });

  testWidgets('queue shows progress; pause, resume and cancel', (tester) async {
    final h = Harness(loader: FakeLoader(gate: Completer<void>()));
    final s = h.service(maxChapters: 1);
    await s.enqueue(mangaKey, ch1);
    await s.enqueue(mangaKey, ch2);
    await _show(tester, s);
    expect(find.text('Ch. 1'), findsOneWidget);
    expect(find.bySemanticsLabel('Downloading 0 / 3'), findsOneWidget);
    expect(find.text(' 0 / 3'), findsOneWidget);
    expect(find.bySemanticsLabel('Queued'), findsOneWidget);
    expect(find.byIcon(Icons.schedule), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Pause downloads'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Paused'), findsOneWidget);
    expect(find.byIcon(Icons.pause_circle_outline), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Resume downloads'));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Cancel').last);
    await tester.pumpAndSettle();
    expect(find.text('Ch. 2'), findsNothing);
    h.loader.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Downloaded'), findsOneWidget);
  });

  test('queue status glyphs', () {
    expect(
      queueStatusIcon(DownloadStatus.done, paused: false),
      Icons.download_done,
    );
    expect(
      queueStatusIcon(DownloadStatus.none, paused: false),
      Icons.downloading,
    );
  });

  testWidgets('a failed chapter can be retried', (tester) async {
    final h = Harness(loader: FakeLoader(failures: 2));
    final s = h.service();
    await s.enqueue(mangaKey, ch1);
    await _show(tester, s);
    expect(find.bySemanticsLabel(RegExp('^Failed: ')), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Retry'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('^Failed: ')), findsNothing);
    expect(find.bySemanticsLabel('Downloaded'), findsOneWidget);
  });

  testWidgets('downloaded chapters: delete one, then all (confirmed)', (
    tester,
  ) async {
    final h = Harness();
    final s = h.service();
    await s.enqueue(mangaKey, ch1);
    await s.enqueue(mangaKey, ch2);
    await _show(tester, s);
    expect(find.text('Berserk'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^2 chapters · ')), findsOneWidget);
    await tester.tap(find.text('Berserk'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('^3 pages · ')), findsNWidgets(2));

    await tester.tap(find.bySemanticsLabel('Delete chapter').first);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Delete Ch. 1?'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Delete'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('^1 chapter · ')), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Delete all chapters'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Berserk'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Delete all chapters'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Delete'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('No downloads'), findsOneWidget);
  });

  testWidgets('a manga missing from the library shows its resolved title', (
    tester,
  ) async {
    final s = Harness().service();
    await s.enqueue(mangaKey, ch1);
    final asked = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: DownloadsScreen(
          service: s,
          titles: Stream.value(const {}),
          resolveTitle: (key) async {
            asked.add(key);
            return 'Berserk (resolved)';
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Berserk (resolved)'), findsOneWidget);
    expect(find.text('/title/1'), findsNothing);
    expect(asked, [mangaKey]);
  });
}
