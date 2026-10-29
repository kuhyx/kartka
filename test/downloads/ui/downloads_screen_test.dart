import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/downloads/download_service.dart';
import 'package:kartka/downloads/ui/downloads_screen.dart';

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
    expect(find.text('No downloads'), findsOneWidget);
    expect(find.text('Storage used: 0 B'), findsOneWidget);
    expect(opened, 1);
  });

  testWidgets('queue shows progress; pause, resume and cancel', (tester) async {
    final h = Harness(loader: FakeLoader(gate: Completer<void>()));
    final s = h.service(maxChapters: 1);
    await s.enqueue(mangaKey, ch1);
    await s.enqueue(mangaKey, ch2);
    await _show(tester, s);
    expect(find.text('Ch. 1'), findsOneWidget);
    expect(find.text('Berserk · Downloading 0 / 3'), findsOneWidget);
    expect(find.text('Berserk · Queued'), findsOneWidget);

    await tester.tap(find.byTooltip('Pause downloads'));
    await tester.pumpAndSettle();
    expect(find.text('Berserk · Paused'), findsOneWidget);
    await tester.tap(find.byTooltip('Resume downloads'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Cancel').last);
    await tester.pumpAndSettle();
    expect(find.text('Ch. 2'), findsNothing);
    h.loader.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Downloaded'), findsOneWidget);
  });

  testWidgets('a failed chapter can be retried', (tester) async {
    final h = Harness(loader: FakeLoader(failures: 2));
    final s = h.service();
    await s.enqueue(mangaKey, ch1);
    await _show(tester, s);
    expect(find.textContaining('Failed: '), findsOneWidget);
    await tester.tap(find.byTooltip('Retry'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Failed: '), findsNothing);
    expect(find.text('Downloaded'), findsOneWidget);
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
    expect(find.textContaining('2 chapters'), findsOneWidget);
    await tester.tap(find.text('Berserk'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Delete chapter').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 chapter ·'), findsOneWidget);

    await tester.tap(find.text('Delete all chapters'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Berserk'), findsOneWidget);

    await tester.tap(find.text('Delete all chapters'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.text('No downloads'), findsOneWidget);
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
