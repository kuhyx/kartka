import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/app/cached_cover.dart';
import 'package:kartka/platform/cover_cache.dart';

import '../browse/ui/harness.dart' show onePixelPng;

Widget _tile(Widget child, {double width = 100}) => MaterialApp(
  home: Center(
    child: SizedBox(width: width, height: 150, child: child),
  ),
);

void main() {
  late int loads;
  late CoverCache cache;

  setUp(() {
    loads = 0;
    cache = CoverCache(
      load: (_) async {
        loads++;
        return onePixelPng;
      },
    );
  });

  testWidgets('a remount shows the cached cover on its first frame', (
    tester,
  ) async {
    await tester.pumpWidget(_tile(CachedCover(url: 'a', loader: cache.get)));
    expect(find.byIcon(Icons.menu_book_outlined), findsOneWidget);
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    // One pump only: no placeholder frame, no second fetch.
    await tester.pumpWidget(_tile(CachedCover(url: 'a', loader: cache.get)));
    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.menu_book_outlined), findsNothing);
    expect(loads, 1);
  });

  testWidgets('decodes at the tile width in device pixels, gapless', (
    tester,
  ) async {
    await tester.pumpWidget(_tile(CachedCover(url: 'a', loader: cache.get)));
    await tester.pump();
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.gaplessPlayback, isTrue);
    expect(image.fit, BoxFit.cover);
    final dpr = tester.view.devicePixelRatio;
    // Rounded up to a 64 px bucket, so small layout changes reuse it.
    final width = (image.image as ResizeImage).width!;
    expect(width % 64, 0);
    expect(width, greaterThanOrEqualTo(100 * dpr));
    expect(width, lessThan(100 * dpr + 64));
  });

  testWidgets('a new url resolves again; no url or loader is a placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(_tile(CachedCover(url: 'a', loader: cache.get)));
    await tester.pumpWidget(_tile(CachedCover(url: 'b', loader: cache.get)));
    await tester.pump();
    expect(loads, 2);
    await tester.pumpWidget(_tile(const CachedCover(url: null, loader: null)));
    expect(find.byIcon(Icons.menu_book_outlined), findsOneWidget);
  });

  testWidgets('a failed load and undecodable bytes show the placeholder', (
    tester,
  ) async {
    Future<Uint8List> failing(String _) async => throw StateError('offline');
    await tester.pumpWidget(_tile(CachedCover(url: 'a', loader: failing)));
    await tester.pump();
    expect(find.byIcon(Icons.menu_book_outlined), findsOneWidget);
    Future<Uint8List> junk(String _) async => Uint8List.fromList([1, 2, 3]);
    await tester.pumpWidget(_tile(CachedCover(url: 'b', loader: junk)));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(find.byIcon(Icons.menu_book_outlined), findsOneWidget);
  });

  testWidgets('an unbounded width decodes at full size', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: UnconstrainedBox(
          child: SizedBox(
            height: 150,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [CachedCover(url: 'a', loader: cache.get)],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.widget<Image>(find.byType(Image)).image, isA<MemoryImage>());
  });
}
