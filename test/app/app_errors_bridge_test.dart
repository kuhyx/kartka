import 'package:crdt_sync_flutter/crdt_sync_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/app/app_errors.dart';
import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The messages of every environment-caused ticket (a server, network or
/// upstream site that is down, a manga the server no longer has): they
/// stay in the device log and never reach `/kartka/errors`.
const _rtdb = 'kuhy-syncs-default-rtdb.europe-west1.firebasedatabase.app';

const _known = {
  'updates.offline':
      'ClientException with SocketException: '
      "Failed host lookup: 'api.mangadex.org' "
      '(OS Error: No address associated with hostname, errno = 7), '
      'uri=https://api.mangadex.org/manga · 208 not checked',
  'downloads.offline':
      'ClientException with SocketException: '
      "Failed host lookup: 'suwayomi.kuhy.duckdns.org' "
      '(OS Error: No address associated with hostname, errno = 7), '
      'uri=https://suwayomi.kuhy.duckdns.org/api/graphql',
  'reader.page': 'KartkaHttpException(500, https://suwayomi.kuhy.duckdns.org/api/v1/manga/281/chapter/39/page/0)',
  'details.load':
      'SuwayomiException: www.blastwave-comic.com: Name or service not known',
  'browse.page':
      'ClientException: Software caused connection abort, '
      'uri=https://suwayomi.kuhy.duckdns.org/api/graphql',
  'reader.open':
      'SuwayomiException: Exception while fetching data (/fetchChapterPages) '
      ': Timed out waiting for WebView after 20s',
  'updates.check':
      'SuwayomiException: not on the server for suwayomi:4709139914729853090',
  'health.read':
      'FirebaseSyncError: network error reading source_health: ClientException '
      "with SocketException: Failed host lookup: '$_rtdb' (OS Error: No "
      'address associated with hostname, errno = 7), uri=https://$_rtdb',
};

const _uncaught = 'ClientException: Connection reset by peer, uri=x';

/// Real bugs keep going up (an escaped one through the shared hook, not
/// the bridge, so it is not queued twice).
const Map<String, String> _bugs = {
  'details.load': 'SuwayomiException: response has no data',
  'reader.page': 'KartkaHttpException(404, https://x.org/api/v1/page/0)',
  'uncaught.flutter': 'Bad state: No element',
  'uncaught.async': _uncaught,
};

void main() {
  test('known environment states stay local; bugs are queued', () async {
    SharedPreferences.setMockInitialValues({});
    final errors = AppErrors.forTest(
      kartkaErrorsConfig(build: 1),
      await ErrorQueue.open(await SharedPreferences.getInstance()),
    );
    final log = DiagnosticsLog(MemoryBlobStore());
    addTearDown(bridgeDiagnostics(log, errors).cancel);
    var s = 0;
    for (final MapEntry(:key, :value) in {..._known, ..._bugs}.entries) {
      await log.append(
        DiagnosticEntry(
          at: DateTime.utc(2026, 11, 17, 12, 0, s++),
          kind: key,
          error: value,
        ),
      );
    }
    for (final MapEntry(:key, :value) in _known.entries) {
      await log.append(
        DiagnosticEntry(
          at: DateTime.utc(2026, 11, 17, 12, 1, s++),
          kind: key == 'reader.page' ? 'downloads.failed' : 'reader.open',
          error: value,
        ),
      );
    }
    await pumpEventQueue();
    final sent = {for (final e in errors.queue.entries) e.error};
    expect(sent, {
      for (final MapEntry(:key, :value) in _bugs.entries)
        if (!key.startsWith('uncaught.')) value,
    });
  });
}
