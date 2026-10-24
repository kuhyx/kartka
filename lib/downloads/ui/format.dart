/// Text helpers for the Downloads UI (pure, unit-tested).
library;

import 'package:kartka/core/models/models.dart';

const _units = ['KB', 'MB', 'GB', 'TB'];

/// `1536` → `1.5 KB`; bytes below 1 KiB stay exact.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < _units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(1)} ${_units[unit]}';
}

/// One-line status of a queued chapter; queued items read "Paused" while
/// the whole queue is [paused].
String statusLine(DownloadState s, {required bool paused}) =>
    switch (s.status) {
      DownloadStatus.none => '',
      DownloadStatus.queued => paused ? 'Paused' : 'Queued',
      DownloadStatus.downloading =>
        s.pagesTotal == 0
            ? 'Downloading…'
            : 'Downloading ${s.pagesDone} / ${s.pagesTotal}',
      DownloadStatus.done => 'Downloaded',
      DownloadStatus.failed =>
        s.error == null ? 'Failed' : 'Failed: ${s.error}',
    };

/// Display title of [key] from library [titles], else its manga url.
String mangaLabel(MangaKey key, Map<MangaKey, String> titles) =>
    titles[key] ?? key.substring(key.indexOf('|') + 1);
