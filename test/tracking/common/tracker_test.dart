import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/tracking/common/tracker.dart';

void main() {
  test('TrackSearchResult compares by value', () {
    const a = TrackSearchResult(remoteId: '1', title: 'A', chapters: 3);
    const b = TrackSearchResult(remoteId: '1', title: 'A', chapters: 3);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a == const TrackSearchResult(remoteId: '2', title: 'A'), isFalse);
    expect(a.toString(), 'TrackSearchResult(1, A)');
  });

  test('TrackStatus compares by value', () {
    const a = TrackStatus(remoteId: '1', chaptersRead: 2, status: 'CURRENT');
    const b = TrackStatus(remoteId: '1', chaptersRead: 2, status: 'CURRENT');
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(
      a == const TrackStatus(remoteId: '1', chaptersRead: 3, status: 'CURRENT'),
      isFalse,
    );
    expect(a.toString(), 'TrackStatus(1, 2, CURRENT)');
  });
}
