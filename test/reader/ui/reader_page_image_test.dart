import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/reader/ui/reader_page_image.dart';

import '../support/fakes.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    Future<Uint8List> bytes, {
    VoidCallback? onRetry,
    bool fitWidth = false,
    Uint8List? initial,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ReaderPageImage(
          bytes: bytes,
          pageNumber: 3,
          onRetry: onRetry ?? () {},
          fitWidth: fitWidth,
          initial: initial,
        ),
      ),
    ),
  );

  testWidgets('shows progress, then the image', (tester) async {
    final done = Completer<Uint8List>();
    await pump(tester, done.future);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    done.complete(onePixelPng);
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);
    expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.contain);
  });

  testWidgets('webtoon pages fit the width', (tester) async {
    await pump(tester, Future.value(onePixelPng), fitWidth: true);
    await tester.pump();
    expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.fitWidth);
  });

  testWidgets('errors offer a retry', (tester) async {
    var retried = 0;
    final failing = Completer<Uint8List>();
    await pump(tester, failing.future, onRetry: () => retried++);
    failing.completeError(StateError('offline'));
    await tester.pump();
    expect(find.textContaining('offline'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(retried, 1);
  });

  testWidgets('undecodable bytes offer a retry too', (tester) async {
    await pump(tester, Future.value(Uint8List.fromList([1, 2, 3])));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('bytes already loaded show on the first frame', (tester) async {
    await pump(tester, Completer<Uint8List>().future, initial: onePixelPng);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(Image), findsOneWidget);
  });
}
