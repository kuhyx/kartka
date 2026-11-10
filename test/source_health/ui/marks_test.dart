import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/source_health/model/quality_metrics.dart';
import 'package:kartka/source_health/model/source_health_record.dart';
import 'package:kartka/source_health/ui/metric_strip.dart';
import 'package:kartka/source_health/ui/source_line_mark.dart';

import '../../helpers/spoken_icon.dart';
import 'harness.dart';

void main() {
  testWidgets('availability: origin glyphs, 0 when none, dash unmeasured', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const Column(
          children: [
            AvailabilityMarks(
              AvailabilityMetric(native: true, keiyoushi: true),
            ),
            AvailabilityMarks(AvailabilityMetric(native: false)),
            AvailabilityMarks(null),
          ],
        ),
      ),
    );
    expect(find.byKey(const Key('av-native')), findsOne);
    expect(find.byKey(const Key('av-suwayomi')), findsOne);
    expect(find.byKey(const Key('av-plugin')), findsNothing);
    expect(find.text('0'), findsOne);
    expect(find.text('—'), findsOne);
    expect(spokenContaining('Available as: none'), findsOne);
  });

  testWidgets('source line: codes painted, a globe for all languages', (
    tester,
  ) async {
    const r = SourceHealthRecord(
      id: 'suwayomi:9',
      name: 'X',
      origin: 'suwayomi',
      lang: 'en',
      langScope: 'unrestricted',
    );
    await tester.pumpWidget(host(const SourceLineMark(r, withId: true)));
    expect(find.byIcon(Icons.public), findsOne);
    expect(find.text('en · suwayomi:9'), findsOne);
    expect(
      spokenContaining('Suwayomi · en · tested all languages · suwayomi:9'),
      findsOne,
    );
  });
}
