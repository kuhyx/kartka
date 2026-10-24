import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/downloads/ui/format.dart';

void main() {
  test('formatBytes uses binary units with one decimal', () {
    expect(formatBytes(0), '0 B');
    expect(formatBytes(1023), '1023 B');
    expect(formatBytes(1536), '1.5 KB');
    expect(formatBytes(5 * 1024 * 1024), '5.0 MB');
    expect(formatBytes(3 * 1024 * 1024 * 1024), '3.0 GB');
  });

  test('statusLine describes each state', () {
    expect(
      statusLine(
        const DownloadState(status: DownloadStatus.queued),
        paused: false,
      ),
      'Queued',
    );
    expect(
      statusLine(
        const DownloadState(status: DownloadStatus.queued),
        paused: true,
      ),
      'Paused',
    );
    expect(
      statusLine(
        const DownloadState(
          status: DownloadStatus.downloading,
          pagesDone: 2,
          pagesTotal: 9,
        ),
        paused: false,
      ),
      'Downloading 2 / 9',
    );
    expect(
      statusLine(
        const DownloadState(status: DownloadStatus.downloading),
        paused: false,
      ),
      'Downloading…',
    );
    expect(
      statusLine(
        const DownloadState(status: DownloadStatus.failed, error: 'HTTP 500'),
        paused: false,
      ),
      'Failed: HTTP 500',
    );
    expect(
      statusLine(
        const DownloadState(status: DownloadStatus.failed),
        paused: false,
      ),
      'Failed',
    );
    expect(statusLine(DownloadState.none, paused: false), '');
    expect(
      statusLine(
        const DownloadState(status: DownloadStatus.done),
        paused: false,
      ),
      'Downloaded',
    );
  });

  test('mangaLabel falls back to the url part of the key', () {
    expect(
      mangaLabel('mangadex|/title/1', {'mangadex|/title/1': 'Berserk'}),
      'Berserk',
    );
    expect(mangaLabel('mangadex|/title/1', {}), '/title/1');
  });
}
