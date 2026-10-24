import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/library/ports.dart';

void main() {
  test('no-op ports report nothing known', () async {
    expect(await const NoUnreadCounts().watch('s|/m').toList(), [null]);
    expect(await const NoDownloadedLookup().hasDownloads('s|/m').toList(), [
      false,
    ]);
    expect(await const NoTrackedLookup().isTracked('s|/m').toList(), [false]);
  });
}
