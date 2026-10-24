import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/downloads/keys.dart';
import 'package:kartka/downloads/queue/download_task.dart';

void main() {
  const chapter = ChapterInfo(url: '/ch/1', name: 'Ch. 1', number: 1);
  final task = DownloadTask(
    mangaKey: 'mangadex|/title/abc',
    chapter: chapter,
    enqueuedAt: DateTime.utc(2026, 10, 24),
  );

  test('defaults to queued with no progress', () {
    expect(task.state.status, DownloadStatus.queued);
    expect(task.sourceId, 'mangadex');
    expect(task.id, taskId('mangadex|/title/abc', '/ch/1'));
  });

  test('round-trips through JSON', () {
    final busy = task.withState(
      const DownloadState(
        status: DownloadStatus.failed,
        pagesDone: 3,
        pagesTotal: 9,
        error: 'HTTP 500',
      ),
    );
    expect(DownloadTask.fromJson(busy.toJson()), busy);
    expect(busy.hashCode, DownloadTask.fromJson(busy.toJson()).hashCode);
    expect(busy, isNot(task));
    expect(task.toString(), contains('/ch/1'));
  });

  test('keys: blob keys are hashed, prefixed and zero-padded', () {
    final prefix = chapterBlobPrefix('m|u', '/c');
    expect(prefix, 'downloads/${keyHash('m|u')}/${keyHash('/c')}/');
    expect(pageBlobKey('m|u', '/c', 7), '${prefix}0007');
    expect(blobPageUrl('k/1'), 'kartka-blob://k/1');
    expect(sourceIdOf('suwayomi:12|/m/1'), 'suwayomi:12');
    expect(sourceIdOf('nobar'), 'nobar');
  });
}
