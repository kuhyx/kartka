import 'dart:async';

import 'package:crdt_sync_flutter/crdt_sync_flutter.dart' show WaitWatch;
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/spoken_icon.dart';
import '../support/fakes.dart';
import 'reader_harness.dart';

/// Fails its first page list, then hangs (a server still fetching).
class _FailsThenHangs extends FakeSource {
  new() : super(chapterList: harnessChapters);

  final hang = Completer<List<PageRef>>();

  @override
  Future<List<PageRef>> pages(String chapterUrl) {
    pageCalls.add(chapterUrl);
    if (pageCalls.length == 1) return Future.error(StateError('upstream'));
    return hang.future;
  }
}

/// An open is timed as `reader.open`; Retry is a tapped probe of a source
/// that just failed (a WebView one takes 20 s each time, 971debc8), so its
/// spinner is not a reported wait, like other button spinners.
void main() {
  testWidgets('the first open is timed, Retry is not', (tester) async {
    final src = _FailsThenHangs();
    final h = ReaderHarness(source: src);
    await h.pump(tester);
    expect(spokenIcon('Retry'), findsOneWidget);
    await tester.tap(spokenIcon('Retry'));
    await h.settle(tester);
    expect(src.pageCalls, hasLength(2));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(WaitWatch), findsNothing);
  });

  testWidgets('a first open that waits is timed', (tester) async {
    final src = _FailsThenHangs()..pageCalls.add('earlier');
    final h = ReaderHarness(source: src);
    await h.pump(tester);
    expect(find.byType(WaitWatch), findsOneWidget);
  });
}
