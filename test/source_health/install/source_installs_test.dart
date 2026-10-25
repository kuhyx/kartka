import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/source_health/install/source_installs.dart';

import 'harness.dart';

void main() {
  test('with no installers given every source opens', () async {
    final ids = StreamController<Set<String>>.broadcast(sync: true);
    final installs = SourceInstalls(sourceIds: ids.stream, open: (_, _) {});
    expect(installs.actionOf(suwayomiRecord()), SourceAction.open);
    installs.dispose();
    await pumpEventQueue();
    expect(ids.hasListener, isFalse);
  });

  test('stripUrls drops whole URLs, path and query alike', () {
    expect(
      stripUrls('GET https://x.test/a/b?key=1#f failed (HTTP://Y/z)'),
      'GET <url> failed (<url>',
    );
  });
}
