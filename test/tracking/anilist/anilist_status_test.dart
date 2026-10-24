import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/tracking/anilist/anilist_status.dart';
import 'package:kartka/tracking/common/tracker.dart';

TrackStatus _entry(String status, {int read = 1, int? total}) => TrackStatus(
  remoteId: '1',
  chaptersRead: read,
  status: status,
  totalChapters: total,
);

void main() {
  test('a new entry starts as CURRENT', () {
    expect(statusAfterPush(current: null, progress: 3), 'CURRENT');
  });

  test('PLANNING, PAUSED and DROPPED resume as CURRENT', () {
    for (final s in ['PLANNING', 'PAUSED', 'DROPPED']) {
      expect(statusAfterPush(current: _entry(s), progress: 2), 'CURRENT');
    }
  });

  test('reaching the total completes the entry', () {
    expect(
      statusAfterPush(current: _entry('CURRENT', total: 10), progress: 10),
      'COMPLETED',
    );
    expect(
      statusAfterPush(current: _entry('PLANNING', total: 5), progress: 6),
      'COMPLETED',
    );
  });

  test('otherwise the status is left alone', () {
    expect(statusAfterPush(current: _entry('CURRENT'), progress: 5), isNull);
    expect(
      statusAfterPush(current: _entry('CURRENT', total: 10), progress: 9),
      isNull,
    );
    expect(statusAfterPush(current: _entry('REPEATING'), progress: 5), isNull);
    expect(statusAfterPush(current: _entry('COMPLETED'), progress: 5), isNull);
    expect(
      statusAfterPush(current: _entry('CURRENT', total: 0), progress: 5),
      isNull,
    );
  });
}
