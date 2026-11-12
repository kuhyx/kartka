import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/downloads/downloads_feature.dart';
import 'package:kartka/downloads/queue/download_task.dart';
import 'package:kartka/platform/memory/memory_stores.dart';

const _lookup =
    "ClientException with SocketException: Failed host lookup: 'h.test' "
    '(OS Error: No address associated with hostname, errno = 7)';

DownloadTask _task(String sourceId, int n) => DownloadTask(
  mangaKey: mangaKeyOf(sourceId, '/m/1'),
  chapter: ChapterInfo(url: '/c/$n', name: 'Ch. $n'),
  enqueuedAt: DateTime.utc(2026),
);

void main() {
  late DiagnosticsLog log;
  late DateTime now;
  late void Function(DownloadTask, Object, StackTrace) report;

  setUp(() {
    log = DiagnosticsLog(MemoryBlobStore());
    now = DateTime.utc(2026, 11, 6, 12);
    report = downloadFailureReporter(log, now: () => now);
  });

  Future<List<(String, String?)>> kinds() async => [
    for (final e in await log.entries()) (e.kind, e.sourceId),
  ];

  test('a queue failing offline reports its server once', () async {
    for (var i = 0; i < 10; i++) {
      final id = i.isEven ? 'suwayomi:1' : 'suwayomi:2';
      report(
        _task(id, i),
        Exception('$_lookup, uri=/page/$i'),
        StackTrace.empty,
      );
    }
    expect(await kinds(), [('downloads.offline', 'suwayomi:1')]);
  });

  test('each unreachable server gets its own entry', () async {
    report(_task('suwayomi:1', 1), Exception(_lookup), StackTrace.empty);
    final other = _lookup.replaceFirst('h.test', 'mangadex.test');
    report(_task('mangadex', 1), Exception(other), StackTrace.empty);
    expect(await kinds(), [
      ('downloads.offline', 'suwayomi:1'),
      ('downloads.offline', 'mangadex'),
    ]);
  });

  test('offline again after the window is reported again', () async {
    report(_task('mangadex', 1), Exception(_lookup), StackTrace.empty);
    now = now.add(offlineReportWindow);
    report(
      _task('mangadex', 2),
      Exception('Network is unreachable'),
      StackTrace.empty,
    );
    expect(await kinds(), hasLength(2));
  });

  test('a failure that is not the network stays downloads.failed', () async {
    report(
      _task('suwayomi:1', 1),
      Exception('SuwayomiException: Timed out waiting for WebView after 20s'),
      StackTrace.empty,
    );
    report(_task('suwayomi:1', 2), StateError('HTTP 503'), StackTrace.empty);
    expect(await kinds(), [
      ('downloads.failed', 'suwayomi:1'),
      ('downloads.failed', 'suwayomi:1'),
    ]);
  });
}
