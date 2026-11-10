import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/library/ports.dart';
import 'package:kartka/updates/state/update_rows.dart';
import 'package:kartka/updates/ui/update_row_tiles.dart';
import 'package:kartka/updates/ui/update_summary_mark.dart';

import '../../helpers/spoken_icon.dart';

Future<void> _show(WidgetTester t, Widget child) =>
    t.pumpWidget(MaterialApp(home: Scaffold(body: child)));

void main() {
  testWidgets('nothing new: a check, no counts, the sentence spoken', (
    t,
  ) async {
    await _show(t, const UpdateSummaryMark(UpdateSummary()));
    expect(find.byIcon(Icons.done_all), findsOneWidget);
    expect(find.byType(Text), findsNothing);
    expect(find.bySemanticsLabel('No new chapters'), findsOneWidget);
  });

  testWidgets('every count gets its own glyph', (t) async {
    const s = UpdateSummary(
      newChapters: 3,
      manga: 2,
      failed: 1,
      notChecked: 4,
      unavailable: 5,
    );
    await _show(t, const UpdateSummaryMark(s));
    for (final (icon, n) in [
      (Icons.fiber_new_outlined, '3'),
      (Icons.collections_bookmark_outlined, '2'),
      (Icons.error_outline, '1'),
      (Icons.cloud_off_outlined, '4'),
      (Icons.extension_off_outlined, '5'),
    ]) {
      expect(find.byIcon(icon), findsOneWidget);
      expect(find.text(n), findsOneWidget);
    }
    expect(find.bySemanticsLabel(s.message), findsOneWidget);
  });

  testWidgets('day headings: glyphs for relative days, dates as text', (
    t,
  ) async {
    for (final label in ['Today', 'Yesterday']) {
      await _show(
        t,
        Builder(builder: (c) => updateRowTile(c, DayRow(label), null)),
      );
      expect(spokenIcon(label), findsOneWidget);
      expect(find.text(label), findsNothing);
    }
    await _show(
      t,
      Builder(
        builder: (c) => updateRowTile(c, const DayRow('2026-01-02'), null),
      ),
    );
    expect(find.text('2026-01-02'), findsOneWidget);
  });
}
