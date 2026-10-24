import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/reader/ui/reader_page_image.dart';

/// A 1x1 transparent PNG.
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

void main() {
  Future<void> pump(
    WidgetTester tester,
    Future<Uint8List> bytes, {
    VoidCallback? onRetry,
    bool fitWidth = false,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ReaderPageImage(
          bytes: bytes,
          pageNumber: 3,
          onRetry: onRetry ?? () {},
          fitWidth: fitWidth,
        ),
      ),
    ),
  );

  testWidgets('shows progress, then the image', (tester) async {
    final done = Completer<Uint8List>();
    await pump(tester, done.future);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    done.complete(_png);
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);
    expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.contain);
  });

  testWidgets('webtoon pages fit the width', (tester) async {
    await pump(tester, Future.value(_png), fitWidth: true);
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
}
