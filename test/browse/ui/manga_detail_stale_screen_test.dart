import 'dart:async';

import 'package:crdt_sync_flutter/crdt_sync_flutter.dart' show WaitWatch;
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/app/routes.dart';
import 'package:kartka/browse/ui/challenge_prompt.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/source/challenge.dart';
import 'package:kartka/core/source/manga_gone_error.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/spoken_icon.dart';
import '../fakes.dart';
import 'harness.dart';

const _url = '/m/1';
final _when = DateTime.utc(2026, 10, 29);

Future<Harness> _stored(
  WidgetTester t,
  FakeSource src, {
  String? sourceId,
}) async {
  t.view.physicalSize = const Size(1200, 2400);
  addTearDown(t.view.resetPhysicalSize);
  final h = Harness(sources: [src]);
  final id = sourceId ?? src.ref.id;
  await h.library.upsert(
    LibraryEntry(
      key: mangaKeyOf(id, _url),
      sourceId: id,
      mangaUrl: _url,
      title: 'Stored title',
      addedAt: _when,
      updatedAt: _when,
    ),
  );
  return h;
}

void main() {
  testWidgets('a stored manga renders at once and refreshes behind a bar', (
    t,
  ) async {
    final src = FakeSource('mangadex');
    final h = await _stored(t, src);
    await h.deps.chapters.load(mangaKeyOf('mangadex', _url));
    src.detailsGate = Completer<void>();
    await h.pump(
      t,
      const SizedBox(),
      at: mangaRoute('mangadex', _url),
      settle: false, // The refresh bar animates until the gate opens.
    );
    await t.pump();
    expect(find.text('Stored title'), findsOneWidget);
    expect(find.bySemanticsLabel('3 chapters'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    // The stored chapters can be read meanwhile: not a wait (2d26b6d5).
    expect(find.byType(WaitWatch, skipOffstage: false), findsNothing);
    src.detailsGate!.complete();
    await t.pumpAndSettle();
    expect(find.text('Detail title'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('a stored manga with no stored chapters times the bar', (
    t,
  ) async {
    final src = FakeSource('mangadex');
    final h = await _stored(t, src);
    src.detailsGate = Completer<void>();
    await h.pump(
      t,
      const SizedBox(),
      at: mangaRoute('mangadex', _url),
      settle: false,
    );
    await t.pump();
    expect(find.text('Stored title'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    // Nothing to read until the list arrives: the reader waits on it.
    final watch = find.byType(WaitWatch, skipOffstage: false);
    expect(watch, findsOneWidget);
    expect(t.widget<WaitWatch>(watch).operation, 'details.refresh');
    src.detailsGate!.complete();
    await t.pumpAndSettle();
  });

  testWidgets('a stored manga shows its list before slow details land', (
    t,
  ) async {
    final src = FakeSource('mangadex')
      ..chaptersGate = Completer<void>()
      ..detailsOnlyGate = Completer<void>();
    final h = await _stored(t, src);
    await h.pump(
      t,
      const SizedBox(),
      at: mangaRoute('mangadex', _url),
      settle: false,
    );
    await t.pump();
    final watch = find.byType(WaitWatch, skipOffstage: false);
    expect(watch, findsOneWidget); // Nothing to read yet.
    src.chaptersGate!.complete();
    await t.pump();
    await t.pump();
    // The list landed, details did not: chapters show, the bar is untimed.
    expect(find.text('Stored title'), findsOneWidget);
    expect(find.bySemanticsLabel('3 chapters'), findsOneWidget);
    expect(watch, findsNothing);
    src.detailsOnlyGate!.complete();
    await t.pumpAndSettle();
    expect(find.text('Detail title'), findsOneWidget);
  });

  testWidgets('a challenge over stored data still offers the prompt', (
    t,
  ) async {
    final src = FakeSource('mangadex')
      ..challenge = ChallengeRequired(Uri.parse('https://x.test/'), 'captcha');
    final h = await _stored(t, src);
    await h.pump(t, const SizedBox(), at: mangaRoute('mangadex', _url));
    expect(find.text('Stored title'), findsOneWidget);
    expect(find.byType(ChallengePrompt), findsOneWidget);
  });

  testWidgets('an unavailable source over stored data says so', (t) async {
    final h = await _stored(
      t,
      FakeSource('mangadex'),
      sourceId: 'sy-builtin:1',
    );
    await h.pump(t, const SizedBox(), at: mangaRoute('sy-builtin:1', _url));
    expect(find.text('Stored title'), findsOneWidget);
    expect(spokenIcon('Source unavailable'), findsOneWidget);
    expect(find.text('sy-builtin:1'), findsOneWidget);
    expect(spokenIcon('Retry'), findsOneWidget);
  });

  testWidgets('a manga gone from the server keeps its details, marked', (
    t,
  ) async {
    final src = FakeSource('mangadex')..failWith = _Gone();
    final h = await _stored(t, src);
    await h.pump(t, const SizedBox(), at: mangaRoute('mangadex', _url));
    await t.pumpAndSettle();
    expect(find.text('Stored title'), findsOneWidget);
    expect(spokenIcon('Not on the server'), findsOneWidget);
    expect(spokenIcon('Retry'), findsOneWidget);
  });
}

class _Gone extends Error implements MangaGoneError {
  @override
  String toString() => 'SuwayomiException: not on the server';
}
