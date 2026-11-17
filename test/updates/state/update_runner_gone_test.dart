import 'package:flutter_test/flutter_test.dart';
import 'package:kartka/browse/state/refresh_outcome.dart';
import 'package:kartka/core/diagnostics/diagnostics.dart';
import 'package:kartka/core/models/models.dart';
import 'package:kartka/core/updates/chapter_update_checker.dart';
import 'package:kartka/platform/memory/memory_stores.dart';
import 'package:kartka/sources/suwayomi/suwayomi_exceptions.dart';
import 'package:kartka/updates/state/update_runner.dart';

/// A manga its server no longer has (3cd8bb71) is a known state: the
/// check counts as failed, but nothing is logged, and the details screen
/// treats it like a missing source (cached details, no report).
void main() {
  test('a manga gone from the server fails its check, unlogged', () async {
    final log = DiagnosticsLog(MemoryBlobStore());
    final key = mangaKeyOf('suwayomi:1', '/gone');
    final runner = UpdateRunner(
      libraryKeys: () async => [key],
      check: (k) async =>
          UpdateFailed(k, SuwayomiNotOnServerException('suwayomi:1', '/gone')),
      diagnostics: log,
      delay: (_) => fail('no retry'),
    );
    final summary = await runner.updateAll();
    expect(summary.failed, 1);
    expect(await log.entries(), isEmpty);
  });

  test('the details screen treats it as a missing source', () {
    expect(
      isMissingSource(SuwayomiNotOnServerException('suwayomi:1', '/gone')),
      isTrue,
    );
  });
}
