import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/migration/candidates/migration_candidate.dart';
import 'package:kartka/migration/walk/candidate_card.dart';
import 'package:material_ui/material_ui.dart';

import '../fakes.dart';

/// A 1x1 transparent PNG.
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00,
  0x0a, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
]);

MigrationCandidate _candidate({
  String? description,
  String? preview,
  ScriptedSource? source,
}) => MigrationCandidate(
  source: source ?? ScriptedSource('s'),
  manga: const MangaSummary(sourceId: 's', url: '/m', title: 'Knight'),
  score: 0.9,
  rank: 0,
  description: description,
  previewChapterUrl: preview,
);

Future<void> _pump(WidgetTester t, Widget card) =>
    t.pumpWidget(MaterialApp(home: Scaffold(body: card)));

void main() {
  testWidgets('shows the description, at most 3 lines', (t) async {
    await _pump(
      t,
      CandidateCard(
        candidate: _candidate(description: 'A knight and a penguin.'),
        loader: null,
      ),
    );
    final text = t.widget<Text>(find.text('A knight and a penguin.'));
    expect(text.maxLines, 3);
  });

  testWidgets('the preview icon loads the first 3 pages', (t) async {
    final asked = <String>[];
    await _pump(
      t,
      CandidateCard(
        candidate: _candidate(preview: '/m/1'),
        loader: null,
        pageLoader: (page) async {
          asked.add(page.imageUrl);
          if (page.index == 2) throw StateError('gone');
          return _png;
        },
      ),
    );
    expect(find.byKey(const ValueKey('previews-/m')), findsNothing);
    await t.tap(find.byIcon(Icons.photo_library_outlined));
    await t.pumpAndSettle();
    expect(asked, ['/m/1#0', '/m/1#1', '/m/1#2']);
    expect(find.byType(Image), findsNWidgets(2));
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    await t.tap(find.byIcon(Icons.photo_library_outlined));
    await t.pump();
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('no loader, no preview chapter: no preview icon', (t) async {
    await _pump(t, CandidateCard(candidate: _candidate(), loader: null));
    expect(find.byIcon(Icons.photo_library_outlined), findsNothing);
    expect(find.byType(Text), findsNWidgets(3)); // title, source, count
  });

  testWidgets('a chapter whose page list fails shows one broken icon', (
    t,
  ) async {
    final source = ScriptedSource('s')..pagesError = StateError('down');
    await _pump(
      t,
      CandidateCard(
        candidate: _candidate(preview: '/m/1', source: source),
        loader: null,
        pageLoader: (_) async => _png,
      ),
    );
    await t.tap(find.byIcon(Icons.photo_library_outlined));
    await t.pumpAndSettle();
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
  });
}
