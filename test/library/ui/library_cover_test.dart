import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/library/ui/library_cover.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: SizedBox(width: 100, height: 150, child: child));

void main() {
  testWidgets('no url or loader shows the placeholder', (tester) async {
    await tester.pumpWidget(_wrap(const LibraryCover(url: null, loader: null)));
    expect(find.byIcon(Icons.menu_book_outlined), findsOneWidget);
  });

  testWidgets('loaded bytes show an image; undecodable bytes fall back', (
    tester,
  ) async {
    var calls = 0;
    Future<Uint8List> loader(String url) async {
      calls++;
      return Uint8List.fromList([1, 2, 3]);
    }

    await tester.pumpWidget(_wrap(LibraryCover(url: 'a', loader: loader)));
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(find.byIcon(Icons.menu_book_outlined), findsOneWidget);

    await tester.pumpWidget(_wrap(LibraryCover(url: 'a', loader: loader)));
    expect(calls, 1);
    await tester.pumpWidget(_wrap(LibraryCover(url: 'b', loader: loader)));
    expect(calls, 2);
  });
}
