import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/downloads/queue/download_queue.dart';
import 'package:kartka/downloads/queue/download_task.dart';

DownloadTask _task(String url, {DownloadStatus s = DownloadStatus.queued}) =>
    DownloadTask(
      mangaKey: 'mangadex|/m',
      chapter: ChapterInfo(url: url, name: url),
      enqueuedAt: DateTime.utc(2026),
      state: DownloadState(status: s, pagesDone: 1, pagesTotal: 4),
    );

void main() {
  test('add keeps order and ignores duplicates', () {
    final q = DownloadQueue()
      ..add(_task('/a'))
      ..add(_task('/b'))
      ..add(_task('/a'));
    expect(q.tasks.map((t) => t.chapter.url), ['/a', '/b']);
    expect(q.byId(_task('/b').id)?.chapter.url, '/b');
    expect(q.byId('missing'), isNull);
  });

  test('a failed task can be re-added and is requeued', () {
    final q = DownloadQueue()..add(_task('/a', s: DownloadStatus.failed));
    expect(q.add(_task('/a')), isTrue);
    expect(q.tasks.single.state.status, DownloadStatus.queued);
    expect(q.add(_task('/a')), isFalse);
  });

  test('update and remove by id', () {
    final q = DownloadQueue()..add(_task('/a'));
    final id = q.tasks.single.id;
    q.update(id, const DownloadState(status: DownloadStatus.downloading));
    expect(q.tasks.single.state.status, DownloadStatus.downloading);
    q.update('missing', DownloadState.none);
    expect(q.remove(id)?.chapter.url, '/a');
    expect(q.remove(id), isNull);
    expect(q.tasks, isEmpty);
  });

  test('runnable skips failed and running tasks, and nothing when paused', () {
    final q = DownloadQueue()
      ..add(_task('/a', s: DownloadStatus.downloading))
      ..add(_task('/b', s: DownloadStatus.failed))
      ..add(_task('/c'));
    expect(q.runnable().map((t) => t.chapter.url), ['/c']);
    q.paused = true;
    expect(q.runnable(), isEmpty);
  });

  test('JSON round-trip turns interrupted downloads back into queued', () {
    final q = DownloadQueue()
      ..add(_task('/a', s: DownloadStatus.downloading))
      ..add(_task('/b', s: DownloadStatus.failed))
      ..paused = true;
    final back = DownloadQueue.fromJson(q.toJson());
    expect(back.paused, isTrue);
    expect(back.tasks.map((t) => t.state.status), [
      DownloadStatus.queued,
      DownloadStatus.failed,
    ]);
    expect(back.tasks.first.state.pagesDone, 1);
  });

  test('decodes null as an empty queue', () {
    final q = DownloadQueue.decode(null);
    expect(q.tasks, isEmpty);
    expect(q.paused, isFalse);
    expect(DownloadQueue.decode(q.encode()).tasks, isEmpty);
  });
}
