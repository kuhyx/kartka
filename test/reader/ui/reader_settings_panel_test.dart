import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/reader/data/reader_settings.dart';
import 'package:kartka/reader/logic/reader_mode.dart';
import 'package:kartka/reader/logic/tap_zones.dart';
import 'package:kartka/reader/ui/reader_controls.dart';
import 'package:kartka/reader/ui/reader_settings_panel.dart';

import '../../helpers/spoken_icon.dart';

void main() {
  testWidgets('every control reports an edited copy', (tester) async {
    final changes = <ReaderSettings>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderSettingsPanel(
            settings: const ReaderSettings(),
            onChanged: changes.add,
          ),
        ),
      ),
    );
    expect(find.byType(Text), findsOneWidget, reason: 'only the count');
    await tester.tap(spokenIcon(ReaderMode.pagedRtl.label));
    await tester.pumpAndSettle();
    await tester.tap(spokenIcon(ReaderMode.webtoon.label).last);
    await tester.pumpAndSettle();
    expect(changes.last.defaultMode, ReaderMode.webtoon);

    await tester.tap(spokenIcon(TapZoneLayout.thirds.label));
    await tester.pumpAndSettle();
    await tester.tap(spokenIcon(TapZoneLayout.kindle.label).last);
    await tester.pumpAndSettle();
    expect(changes.last.tapLayout, TapZoneLayout.kindle);

    await tester.tap(find.byType(Slider));
    await tester.pumpAndSettle();
    expect(changes.last.prefetchAhead, 5);
  });

  testWidgets('controls label downloaded chapters', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderControls(
            title: 'Ch. 1',
            offline: true,
            mode: ReaderMode.pagedRtl,
            page: 0,
            pageCount: 3,
            onBack: () {},
            onMode: (_) {},
            onFullscreen: () {},
            onSettings: () {},
            onPage: (_) {},
          ),
        ),
      ),
    );
    expect(spokenIcon('Downloaded'), findsOneWidget);
    expect(find.text('Ch. 1'), findsOneWidget);
  });
}
