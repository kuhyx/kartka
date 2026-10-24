import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/app/routes.dart';
import 'package:kartka/core/models/models.dart';

import '../fake_download_service.dart';
import 'harness.dart';

const _url = '/manga/a b?c=1#d';

Future<Harness> _open(WidgetTester t, {FakeDownloadService? service}) async {
  t.view.physicalSize = const Size(1200, 2400);
  addTearDown(t.view.resetPhysicalSize);
  final h = Harness(downloadService: service);
  await h.pump(t, const SizedBox(), at: mangaRoute('mangadex', _url));
  return h;
}

Finder _in(String chapterUrl, Finder f) => find.descendant(
  of: find.byKey(ValueKey('chapter-$chapterUrl')),
  matching: f,
);

void main() {
  testWidgets('queued or downloading: cancel; then it can be downloaded', (
    t,
  ) async {
    final s = FakeDownloadService()
      ..states['/c/3'] = const DownloadState(status: DownloadStatus.queued)
      ..states['/c/2'] = const DownloadState(
        status: DownloadStatus.downloading,
        pagesDone: 3,
        pagesTotal: 10,
      );
    await _open(t, service: s);
    expect(_in('/c/3', find.byTooltip('Cancel download')), findsOneWidget);
    expect(_in('/c/2', find.byTooltip('Cancel download')), findsOneWidget);
    expect(_in('/c/1', find.byTooltip('Download')), findsOneWidget);
    await t.tap(_in('/c/2', find.byTooltip('Cancel download')));
    await t.pumpAndSettle();
    expect(s.calls, ['cancel:/c/2']);
    expect(_in('/c/2', find.byTooltip('Download')), findsOneWidget);
    await t.tap(_in('/c/2', find.byTooltip('Download')));
    await t.pumpAndSettle();
    expect(s.calls.last, 'enqueue:/c/2');
    expect(_in('/c/2', find.byTooltip('Cancel download')), findsOneWidget);
  });

  testWidgets('downloaded: delete', (t) async {
    final s = FakeDownloadService()
      ..states['/c/1'] = const DownloadState(
        status: DownloadStatus.done,
        pagesDone: 5,
        pagesTotal: 5,
      );
    await _open(t, service: s);
    expect(find.byTooltip('Delete download'), findsOneWidget);
    await t.tap(find.byTooltip('Delete download'));
    await t.pumpAndSettle();
    expect(s.calls, ['delete:/c/1']);
    expect(find.byTooltip('Delete download'), findsNothing);
    expect(_in('/c/1', find.byTooltip('Download')), findsOneWidget);
  });

  testWidgets('failed: download again', (t) async {
    final s = FakeDownloadService()
      ..states['/c/1'] = const DownloadState(
        status: DownloadStatus.failed,
        error: 'boom',
      );
    await _open(t, service: s);
    await t.tap(_in('/c/1', find.byTooltip('Download failed: retry')));
    await t.pumpAndSettle();
    expect(s.calls, ['enqueue:/c/1']);
  });

  testWidgets('no DownloadService: cancel and delete are hidden', (t) async {
    final h = Harness();
    h.downloads.enqueued.add('/c/3');
    t.view.physicalSize = const Size(1200, 2400);
    addTearDown(t.view.resetPhysicalSize);
    await h.pump(t, const SizedBox(), at: mangaRoute('mangadex', _url));
    expect(find.byTooltip('Cancel download'), findsNothing);
    expect(find.byTooltip('Delete download'), findsNothing);
    expect(_in('/c/3', find.byTooltip('Download')), findsNothing);
    expect(_in('/c/3', find.byTooltip('Queued')), findsOneWidget);
    expect(_in('/c/2', find.byTooltip('Download')), findsOneWidget);
  });
}
