import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/app/routes.dart';
import 'package:kartka/browse/ui/challenge_prompt.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/source/challenge.dart';

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
    src.detailsGate!.complete();
    await t.pumpAndSettle();
    expect(find.text('Detail title'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
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
}
